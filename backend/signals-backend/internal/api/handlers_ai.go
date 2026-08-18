package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"signals-backend/internal/domain"
	"signals-backend/internal/store"
)

const maxQuestionLen = 500

const aiSummarySystemPrompt = `You are summarizing device signal observation data for the operator of an internal data-collection tool. You will be given aggregate JSON statistics (counts by type/device, a date range, and the densest observation grid cells) -- never raw records. Write a concise, factual 3-5 sentence summary covering volume, notable devices, and any geographic hotspots. Do not speculate beyond the given numbers.`

const aiAskSystemPrompt = `You are answering an operator's question about device signal observation data for an internal data-collection tool. You will be given aggregate JSON statistics (counts by type/device, a date range, and the densest observation grid cells) -- never raw records. Answer using ONLY this data. If the data doesn't contain the answer, say so explicitly rather than guessing.`

// aiFilters is the shared query-param filter set for both AI endpoints,
// parsed the same way as handleSignalsHeatmap's filters plus an optional
// time range.
type aiFilters struct {
	DeviceID   string
	SignalType string
	Since      *time.Time
	Until      *time.Time
}

func parseAIFilters(r *http.Request) (aiFilters, error) {
	f := aiFilters{
		DeviceID:   r.URL.Query().Get("device_id"),
		SignalType: r.URL.Query().Get("signal_type"),
	}
	if f.SignalType != "" && !domain.ValidSignalTypes[f.SignalType] {
		return aiFilters{}, fmt.Errorf("invalid_signal_type")
	}
	if v := r.URL.Query().Get("since"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			return aiFilters{}, fmt.Errorf("invalid_since")
		}
		f.Since = &t
	}
	if v := r.URL.Query().Get("until"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			return aiFilters{}, fmt.Errorf("invalid_until")
		}
		f.Until = &t
	}
	return f, nil
}

type aiDataContext struct {
	Stats       store.SignalStats    `json:"stats"`
	TopHotspots []store.HeatmapPoint `json:"top_hotspots"`
}

// buildDataContext gathers aggregate stats + top density cells for the given
// filters and marshals them into a compact JSON blob to use as LLM context.
// Deliberately never includes raw signal payloads -- see the AI feature
// design note in CLAUDE.md.
func (s *Server) buildDataContext(ctx context.Context, f aiFilters) (string, error) {
	stats, err := s.db.SignalStats(ctx, store.StatsOpts{
		DeviceID:   f.DeviceID,
		SignalType: f.SignalType,
		Since:      f.Since,
		Until:      f.Until,
	})
	if err != nil {
		return "", fmt.Errorf("fetching stats: %w", err)
	}

	points, err := s.db.HeatmapPoints(ctx, store.HeatmapOpts{
		DeviceID:   f.DeviceID,
		SignalType: f.SignalType,
		Precision:  defaultHeatmapPrecision,
	})
	if err != nil {
		return "", fmt.Errorf("fetching hotspots: %w", err)
	}
	if len(points) > 5 {
		points = points[:5]
	}

	blob, err := json.Marshal(aiDataContext{Stats: stats, TopHotspots: points})
	if err != nil {
		return "", fmt.Errorf("marshaling context: %w", err)
	}
	return string(blob), nil
}

type aiSummaryResponse struct {
	Summary string `json:"summary"`
}

// handleAISummary generates a natural-language summary of observations
// matching the given filters via the configured LLM.
func (s *Server) handleAISummary(w http.ResponseWriter, r *http.Request) {
	if s.llm == nil {
		writeError(w, http.StatusServiceUnavailable, "ai_not_configured")
		return
	}
	filters, err := parseAIFilters(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	dataContext, err := s.buildDataContext(r.Context(), filters)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "context_build_failed")
		return
	}

	summary, err := s.llm.Complete(r.Context(), aiSummarySystemPrompt, dataContext)
	if err != nil {
		writeError(w, http.StatusBadGateway, "llm_request_failed")
		return
	}

	writeJSON(w, http.StatusOK, aiSummaryResponse{Summary: summary})
}

type aiAskRequest struct {
	Question   string `json:"question"`
	DeviceID   string `json:"device_id"`
	SignalType string `json:"signal_type"`
	Since      string `json:"since"`
	Until      string `json:"until"`
}

type aiAskResponse struct {
	Answer string `json:"answer"`
}

// handleAIAsk answers a free-text question about observations matching the
// given filters via the configured LLM, grounded in aggregate data only.
func (s *Server) handleAIAsk(w http.ResponseWriter, r *http.Request) {
	if s.llm == nil {
		writeError(w, http.StatusServiceUnavailable, "ai_not_configured")
		return
	}

	var req aiAskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	question := strings.TrimSpace(req.Question)
	if question == "" {
		writeError(w, http.StatusBadRequest, "question_required")
		return
	}
	if len(question) > maxQuestionLen {
		writeError(w, http.StatusBadRequest, "question_too_long")
		return
	}
	if req.SignalType != "" && !domain.ValidSignalTypes[req.SignalType] {
		writeError(w, http.StatusBadRequest, "invalid_signal_type")
		return
	}

	filters := aiFilters{DeviceID: req.DeviceID, SignalType: req.SignalType}
	if req.Since != "" {
		t, err := time.Parse(time.RFC3339, req.Since)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid_since")
			return
		}
		filters.Since = &t
	}
	if req.Until != "" {
		t, err := time.Parse(time.RFC3339, req.Until)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid_until")
			return
		}
		filters.Until = &t
	}

	dataContext, err := s.buildDataContext(r.Context(), filters)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "context_build_failed")
		return
	}

	prompt := fmt.Sprintf("Data:\n%s\n\nQuestion: %s", dataContext, question)
	answer, err := s.llm.Complete(r.Context(), aiAskSystemPrompt, prompt)
	if err != nil {
		writeError(w, http.StatusBadGateway, "llm_request_failed")
		return
	}

	writeJSON(w, http.StatusOK, aiAskResponse{Answer: answer})
}

// handleAIPage serves the self-contained HTML/JS AI summary/Q&A viewer.
func (s *Server) handleAIPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(aiPageHTML))
}

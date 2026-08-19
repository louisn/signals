package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"signals-backend/internal/domain"
	"signals-backend/internal/store"
)

// handlePostSignalBatch ingests a batch of signals from an authenticated
// device. It is safe to retry: a batch already recorded under its batch_id
// short-circuits to the stored result instead of reprocessing, and
// individual records are inserted with ON CONFLICT DO NOTHING on their
// (id, captured_at) key.
func (s *Server) handlePostSignalBatch(w http.ResponseWriter, r *http.Request) {
	var req domain.BatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}
	if err := domain.ValidateBatchRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	token := tokenFromContext(r.Context())
	device, err := s.db.AuthenticateDevice(r.Context(), req.DeviceID, token)
	if errors.Is(err, store.ErrDeviceNotFound) {
		writeError(w, http.StatusUnauthorized, "invalid_device_or_token")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "auth_lookup_failed")
		return
	}
	if device.Disabled {
		writeError(w, http.StatusForbidden, "device_disabled")
		return
	}

	if already, err := s.db.BatchAlreadyProcessed(r.Context(), req.BatchID); err == nil && already {
		ids, err := s.db.AcceptedIDsForBatch(r.Context(), req.BatchID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "batch_lookup_failed")
			return
		}
		writeJSON(w, http.StatusOK, domain.BatchResponse{BatchID: req.BatchID, Accepted: ids, Rejected: nil})
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "batch_lookup_failed")
		return
	}

	now := time.Now().UTC()
	var accepted []domain.Signal
	var rejected []domain.RejectedSignal
	for _, sig := range req.Signals {
		if reason := domain.ValidateSignal(sig, now); reason != "" {
			rejected = append(rejected, domain.RejectedSignal{ID: sig.ID, Reason: reason})
			log.Printf("rejected signal id=%s device=%s type=%s captured_at=%s reason=%s",
				sig.ID, req.DeviceID, sig.SignalType, sig.CapturedAt, reason)
			continue
		}
		accepted = append(accepted, sig)
	}
	log.Printf("batch %s from device %s: %d accepted, %d rejected", req.BatchID, req.DeviceID, len(accepted), len(rejected))

	if len(accepted) > 0 {
		if err := s.db.InsertBatch(r.Context(), device.ID, req.BatchID, accepted, len(rejected)); err != nil {
			writeError(w, http.StatusInternalServerError, "insert_failed")
			return
		}
	}

	if err := s.db.TouchDevice(r.Context(), device.ID, req.AppVersion, req.OSVersion); err != nil {
		writeError(w, http.StatusInternalServerError, "device_touch_failed")
		return
	}

	acceptedIDs := make([]string, 0, len(accepted))
	for _, sig := range accepted {
		acceptedIDs = append(acceptedIDs, sig.ID)
	}

	writeJSON(w, http.StatusOK, domain.BatchResponse{
		BatchID:  req.BatchID,
		Accepted: acceptedIDs,
		Rejected: rejected,
	})
}

const (
	defaultSignalsPageLimit = 50
	maxSignalsPageLimit     = 200
)

type listSignalsResponse struct {
	Signals []store.SignalRow `json:"signals"`
	Total   int               `json:"total"`
	Limit   int               `json:"limit"`
	Offset  int               `json:"offset"`
	HasMore bool              `json:"has_more"`
}

// handleListSignals serves the observations backing the admin viewer as
// JSON, filtered/paginated via query params. Admin-only: signal payloads
// (BLE names, network metadata) aren't meant for device-scoped bearer auth.
func (s *Server) handleListSignals(w http.ResponseWriter, r *http.Request) {
	limit := defaultSignalsPageLimit
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= maxSignalsPageLimit {
			limit = n
		}
	}
	offset := 0
	if v := r.URL.Query().Get("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}
	signalType := r.URL.Query().Get("signal_type")
	if signalType != "" && !domain.ValidSignalTypes[signalType] {
		writeError(w, http.StatusBadRequest, "invalid_signal_type")
		return
	}

	listOpts := store.ListSignalsOpts{
		DeviceID:   r.URL.Query().Get("device_id"),
		SignalType: signalType,
		Limit:      limit,
		Offset:     offset,
	}
	rows, err := s.db.ListSignals(r.Context(), listOpts)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list_failed")
		return
	}

	total, err := s.db.CountSignals(r.Context(), listOpts)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "count_failed")
		return
	}

	writeJSON(w, http.StatusOK, listSignalsResponse{
		Signals: rows,
		Total:   total,
		Limit:   limit,
		Offset:  offset,
		HasMore: offset+len(rows) < total,
	})
}

// handleSignalsPage serves the self-contained HTML/JS observation viewer,
// which fetches /admin/signals.json for its data.
func (s *Server) handleSignalsPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(signalsPageHTML))
}

const (
	defaultHeatmapPrecision = 3
	minHeatmapPrecision     = 1
	maxHeatmapPrecision     = 6
)

type heatmapResponse struct {
	Points    []store.HeatmapPoint `json:"points"`
	Precision int                  `json:"precision"`
}

// handleSignalsHeatmap serves grid-binned observation density as JSON, for
// the heat map viewer to render as a Leaflet heat layer.
func (s *Server) handleSignalsHeatmap(w http.ResponseWriter, r *http.Request) {
	precision := defaultHeatmapPrecision
	if v := r.URL.Query().Get("precision"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= minHeatmapPrecision && n <= maxHeatmapPrecision {
			precision = n
		}
	}
	signalType := r.URL.Query().Get("signal_type")
	if signalType != "" && !domain.ValidSignalTypes[signalType] {
		writeError(w, http.StatusBadRequest, "invalid_signal_type")
		return
	}

	points, err := s.db.HeatmapPoints(r.Context(), store.HeatmapOpts{
		DeviceID:   r.URL.Query().Get("device_id"),
		SignalType: signalType,
		Precision:  precision,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "heatmap_failed")
		return
	}

	writeJSON(w, http.StatusOK, heatmapResponse{Points: points, Precision: precision})
}

// handleHeatmapPage serves the self-contained HTML/JS heat map viewer, which
// fetches /admin/signals/heatmap.json for its data.
func (s *Server) handleHeatmapPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(heatmapPageHTML))
}

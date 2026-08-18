package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"signals-backend/internal/llm"
	"signals-backend/internal/store"
)

type Server struct {
	db        *store.Postgres
	adminKey  string
	viewerKey string
	llm       *llm.Client
	router    chi.Router
}

func NewServer(db *store.Postgres, adminKey, viewerKey string, llmClient *llm.Client) *Server {
	s := &Server{db: db, adminKey: adminKey, viewerKey: viewerKey, llm: llmClient}
	s.router = s.routes()
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.router.ServeHTTP(w, r)
}

func (s *Server) routes() chi.Router {
	r := chi.NewRouter()

	r.Get("/v1/health", s.handleHealth)

	r.Group(func(r chi.Router) {
		r.Use(s.deviceAuth)
		r.Post("/v1/signals/batches", s.handlePostSignalBatch)
	})

	r.Group(func(r chi.Router) {
		r.Use(s.adminAuth)
		r.Post("/v1/devices", s.handleCreateDevice)
	})
	r.Get("/v1/devices/{id}", s.handleGetDevice)

	r.Group(func(r chi.Router) {
		r.Use(s.adminBasicAuth)
		r.Get("/admin/signals", s.handleSignalsPage)
		r.Get("/admin/signals.json", s.handleListSignals)
		r.Get("/admin/signals/heatmap", s.handleHeatmapPage)
		r.Get("/admin/signals/heatmap.json", s.handleSignalsHeatmap)
		r.Get("/admin/ai", s.handleAIPage)
		r.Get("/admin/ai/summary.json", s.handleAISummary)
		r.Post("/admin/ai/ask", s.handleAIAsk)
	})

	return r
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, reason string) {
	writeJSON(w, status, map[string]string{"error": reason})
}

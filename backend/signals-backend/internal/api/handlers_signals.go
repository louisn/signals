package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
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

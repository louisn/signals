package api

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"signals-backend/internal/store"
)

type createDeviceRequest struct {
	// DeviceID, when present, must match the UUID the client already
	// generated and persisted in its own Keychain (see DeviceIdentity on
	// iOS) -- that ID is what every subsequent signal batch is submitted
	// under, so provisioning must register the SAME id rather than minting
	// an unrelated one the client would then have no way to learn.
	DeviceID string `json:"device_id"`
	Label    string `json:"label"`
}

type createDeviceResponse struct {
	DeviceID string `json:"device_id"`
	APIKey   string `json:"api_key"`
}

func generateAPIKey() (string, error) {
	buf := make([]byte, 32) // 256 bits
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

// handleCreateDevice provisions a new device and returns its bearer token
// once. The token is never stored or re-displayed after this response.
func (s *Server) handleCreateDevice(w http.ResponseWriter, r *http.Request) {
	var req createDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return
	}

	deviceID := req.DeviceID
	if deviceID == "" {
		deviceID = uuid.NewString()
	} else if _, err := uuid.Parse(deviceID); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_device_id")
		return
	}

	apiKey, err := generateAPIKey()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "key_generation_failed")
		return
	}

	// Upsert rather than plain insert: an app reinstall keeps its
	// Keychain-persisted device_id, so re-provisioning the same physical
	// device must issue a fresh key rather than failing on the existing row.
	if err := s.db.UpsertDevice(r.Context(), deviceID, store.HashAPIKey(apiKey), req.Label); err != nil {
		writeError(w, http.StatusInternalServerError, "device_creation_failed")
		return
	}

	writeJSON(w, http.StatusCreated, createDeviceResponse{DeviceID: deviceID, APIKey: apiKey})
}

// handleGetDevice is an internal/admin lookup, unauthenticated in v1 since
// it exposes no secrets (no api_key field) -- add adminAuth here too if
// device labels/status become sensitive.
func (s *Server) handleGetDevice(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	info, err := s.db.GetDevice(r.Context(), id)
	if errors.Is(err, store.ErrDeviceNotFound) {
		writeError(w, http.StatusNotFound, "device_not_found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "lookup_failed")
		return
	}
	writeJSON(w, http.StatusOK, info)
}

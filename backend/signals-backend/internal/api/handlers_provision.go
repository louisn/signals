package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"

	"github.com/google/uuid"

	"signals-backend/internal/store"
)

// handleProvisionQR provisions a fresh device and renders a scannable QR
// encoding a `signals://connect` deep link. The operator opens this page in a
// browser on a real computer (admin Basic-auth handles the credential prompt),
// then the target phone scans the QR with its stock camera app -- which opens
// the app via the deep link and hands it the credential. No secret is ever
// typed on the phone, and the admin key never touches it.
//
// Tradeoff: the device bearer token rides inside the QR, so treat the rendered
// page as sensitive (it is already behind adminBasicAuth). A pairing-code flow
// would keep the token out of the QR entirely, at the cost of backend session
// state -- deliberately not built yet.
func (s *Server) handleProvisionQR(w http.ResponseWriter, r *http.Request) {
	label := r.URL.Query().Get("label")
	if label == "" {
		label = "qr-provisioned"
	}

	deviceID := uuid.NewString()
	apiKey, err := generateAPIKey()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "key_generation_failed")
		return
	}
	if err := s.db.UpsertDevice(r.Context(), deviceID, store.HashAPIKey(apiKey), label); err != nil {
		writeError(w, http.StatusInternalServerError, "device_creation_failed")
		return
	}

	scheme := "https"
	if p := r.Header.Get("X-Forwarded-Proto"); p != "" {
		scheme = p
	}
	base := scheme + "://" + r.Host

	link := "signals://connect?" + url.Values{
		"base":      {base},
		"device_id": {deviceID},
		"key":       {apiKey},
	}.Encode()

	// JSON-encode the link so it embeds safely as a JS string literal.
	linkJS, _ := json.Marshal(link)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = fmt.Fprintf(w, provisionQRPageHTML, label, deviceID, linkJS)
}

const provisionQRPageHTML = `<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Connect a device</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 480px; margin: 2rem auto; padding: 0 1rem; color: #111; }
  #qr { display: flex; justify-content: center; margin: 1.5rem 0; }
  .meta { color: #555; font-size: 0.9rem; word-break: break-all; }
  .warn { background: #fff5e6; border: 1px solid #f0c674; padding: 0.75rem; border-radius: 6px; font-size: 0.85rem; }
</style></head>
<body>
  <h1>Connect a device</h1>
  <p>Scan this with the phone's <strong>Camera</strong> app, then tap the pop-up to open Signals.</p>
  <div id="qr"></div>
  <p class="meta">Device: %s<br>ID: %s</p>
  <p class="warn">This QR carries a device credential. Reload the page to provision a fresh device (each load mints a new one).</p>
  <script>new QRCode(document.getElementById("qr"), { text: %s, width: 280, height: 280 });</script>
</body></html>`

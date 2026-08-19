package domain

import (
	"encoding/json"
	"time"
)

const (
	SignalTypeLocation         = "location"
	SignalTypeBLEAdvertisement = "ble_advertisement"
	SignalTypeNetworkMetadata  = "network_metadata"
	// Android-only capture types. iOS can't enumerate nearby Wi-Fi access
	// points or neighboring cell towers (no public API); the Android client
	// can, so these carry richer data (BSSIDs/MACs, cell identities) that the
	// iOS network_metadata type deliberately omits.
	SignalTypeWiFiScan = "wifi_scan"
	SignalTypeCellInfo = "cell_info"
)

var ValidSignalTypes = map[string]bool{
	SignalTypeLocation:         true,
	SignalTypeBLEAdvertisement: true,
	SignalTypeNetworkMetadata:  true,
	SignalTypeWiFiScan:         true,
	SignalTypeCellInfo:         true,
}

type LocationTag struct {
	Lat                 float64  `json:"lat"`
	Lon                 float64  `json:"lon"`
	HorizontalAccuracyM *float64 `json:"horizontal_accuracy_m,omitempty"`
	AgeS                *float64 `json:"age_s,omitempty"`
}

// Signal is a single client-submitted record within a batch.
type Signal struct {
	ID         string          `json:"id"`
	CapturedAt time.Time       `json:"captured_at"`
	SignalType string          `json:"signal_type"`
	Location   *LocationTag    `json:"location,omitempty"`
	Payload    json.RawMessage `json:"payload"`
}

// BatchRequest is the POST /v1/signals/batches request body.
type BatchRequest struct {
	DeviceID   string   `json:"device_id"`
	AppVersion string   `json:"app_version"`
	OSVersion  string   `json:"os_version"`
	BatchID    string   `json:"batch_id"`
	Signals    []Signal `json:"signals"`
}

type RejectedSignal struct {
	ID     string `json:"id"`
	Reason string `json:"reason"`
}

type BatchResponse struct {
	BatchID  string           `json:"batch_id"`
	Accepted []string         `json:"accepted"`
	Rejected []RejectedSignal `json:"rejected"`
}

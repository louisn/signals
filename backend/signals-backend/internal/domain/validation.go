package domain

import (
	"fmt"
	"time"
)

const maxFutureSkew = 5 * time.Minute
const maxPastAge = 30 * 24 * time.Hour

// ValidateSignal checks a single record for acceptability, independent of
// any other records in its batch. It returns a rejection reason, or "" if
// the signal is acceptable.
func ValidateSignal(s Signal, now time.Time) string {
	if s.ID == "" {
		return "missing_id"
	}
	if !ValidSignalTypes[s.SignalType] {
		return "invalid_signal_type"
	}
	if s.CapturedAt.After(now.Add(maxFutureSkew)) {
		return "captured_at_in_future"
	}
	if s.CapturedAt.Before(now.Add(-maxPastAge)) {
		return "captured_at_too_old"
	}
	if s.Location != nil {
		if s.Location.Lat < -90 || s.Location.Lat > 90 {
			return "invalid_latitude"
		}
		if s.Location.Lon < -180 || s.Location.Lon > 180 {
			return "invalid_longitude"
		}
	}
	if len(s.Payload) == 0 {
		return "missing_payload"
	}
	return ""
}

func ValidateBatchRequest(req BatchRequest) error {
	if req.DeviceID == "" {
		return fmt.Errorf("missing device_id")
	}
	if req.BatchID == "" {
		return fmt.Errorf("missing batch_id")
	}
	if len(req.Signals) == 0 {
		return fmt.Errorf("empty signals array")
	}
	if len(req.Signals) > 500 {
		return fmt.Errorf("batch exceeds max size of 500 records")
	}
	return nil
}

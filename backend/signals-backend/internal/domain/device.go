package domain

import "time"

type Device struct {
	ID          string
	APIKeyHash  string
	Label       string
	FirstSeenAt time.Time
	LastSeenAt  *time.Time
	AppVersion  string
	OSVersion   string
	Disabled    bool
}

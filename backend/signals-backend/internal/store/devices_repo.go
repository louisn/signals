package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"

	"github.com/jackc/pgx/v5"
)

var ErrDeviceNotFound = errors.New("device not found")

type DeviceRow struct {
	ID       string
	Disabled bool
}

func HashAPIKey(key string) string {
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])
}

// UpsertDevice creates a new device row, or -- if id already exists (a
// reinstalled app re-provisioning with its Keychain-persisted id) --
// rotates its api_key_hash and label rather than failing on the conflict.
func (p *Postgres) UpsertDevice(ctx context.Context, id, apiKeyHash, label string) error {
	_, err := p.Pool.Exec(ctx, `
		INSERT INTO devices (id, api_key_hash, label) VALUES ($1, $2, $3)
		ON CONFLICT (id) DO UPDATE SET api_key_hash = EXCLUDED.api_key_hash, label = EXCLUDED.label`,
		id, apiKeyHash, label,
	)
	return err
}

// AuthenticateDevice looks up a device by its bearer token's hash and
// confirms the token belongs to the claimed device_id.
func (p *Postgres) AuthenticateDevice(ctx context.Context, claimedDeviceID, apiKey string) (*DeviceRow, error) {
	hash := HashAPIKey(apiKey)
	var row DeviceRow
	err := p.Pool.QueryRow(ctx,
		`SELECT id, disabled FROM devices WHERE id = $1 AND api_key_hash = $2`,
		claimedDeviceID, hash,
	).Scan(&row.ID, &row.Disabled)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrDeviceNotFound
	}
	if err != nil {
		return nil, err
	}
	return &row, nil
}

type DeviceInfo struct {
	ID          string
	Label       string
	FirstSeenAt string
	LastSeenAt  *string
	AppVersion  string
	OSVersion   string
	Disabled    bool
}

func (p *Postgres) GetDevice(ctx context.Context, id string) (*DeviceInfo, error) {
	var info DeviceInfo
	err := p.Pool.QueryRow(ctx, `
		SELECT id, label, first_seen_at::text, last_seen_at::text, app_version, os_version, disabled
		FROM devices WHERE id = $1`, id,
	).Scan(&info.ID, &info.Label, &info.FirstSeenAt, &info.LastSeenAt, &info.AppVersion, &info.OSVersion, &info.Disabled)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrDeviceNotFound
	}
	if err != nil {
		return nil, err
	}
	return &info, nil
}

func (p *Postgres) TouchDevice(ctx context.Context, id, appVersion, osVersion string) error {
	_, err := p.Pool.Exec(ctx,
		`UPDATE devices SET last_seen_at = now(), app_version = $2, os_version = $3 WHERE id = $1`,
		id, appVersion, osVersion,
	)
	return err
}

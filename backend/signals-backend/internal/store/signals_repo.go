package store

import (
	"context"
	"encoding/json"
	"time"

	"signals-backend/internal/domain"
)

// InsertBatch writes accepted signals and the batch summary row in a single
// transaction. Signals are inserted with ON CONFLICT DO NOTHING on their
// (id, captured_at) primary key so retried batches are safe to resubmit.
func (p *Postgres) InsertBatch(ctx context.Context, deviceID, batchID string, signals []domain.Signal, rejectedCount int) error {
	tx, err := p.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, s := range signals {
		var lat, lon, hAcc, ageS *float64
		if s.Location != nil {
			lat = &s.Location.Lat
			lon = &s.Location.Lon
			hAcc = s.Location.HorizontalAccuracyM
			ageS = s.Location.AgeS
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO signals (id, device_id, captured_at, signal_type, lat, lon,
				horizontal_accuracy_m, location_age_s, payload, batch_id)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
			ON CONFLICT (id, captured_at) DO NOTHING`,
			s.ID, deviceID, s.CapturedAt, s.SignalType, lat, lon, hAcc, ageS, s.Payload, batchID,
		)
		if err != nil {
			return err
		}
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO upload_batches (id, device_id, record_count, accepted_count, rejected_count)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (id) DO NOTHING`,
		batchID, deviceID, len(signals)+rejectedCount, len(signals), rejectedCount,
	)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// BatchAlreadyProcessed reports whether a batch with this ID has already
// been recorded, so a retried request can short-circuit without
// reprocessing (still returns true membership info via signal ids).
func (p *Postgres) BatchAlreadyProcessed(ctx context.Context, batchID string) (bool, error) {
	var exists bool
	err := p.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM upload_batches WHERE id = $1)`, batchID,
	).Scan(&exists)
	return exists, err
}

// AcceptedIDsForBatch returns the signal IDs already stored under this
// batch, used to rebuild an idempotent response on retry.
func (p *Postgres) AcceptedIDsForBatch(ctx context.Context, batchID string) ([]string, error) {
	rows, err := p.Pool.Query(ctx, `SELECT id FROM signals WHERE batch_id = $1`, batchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// SignalRow is a single observation as returned to the admin viewer.
type SignalRow struct {
	ID         string          `json:"id"`
	DeviceID   string          `json:"device_id"`
	CapturedAt time.Time       `json:"captured_at"`
	SignalType string          `json:"signal_type"`
	Lat        *float64        `json:"lat,omitempty"`
	Lon        *float64        `json:"lon,omitempty"`
	Payload    json.RawMessage `json:"payload"`
}

// ListSignalsOpts filters/paginates ListSignals. Empty DeviceID/SignalType
// means "no filter" -- callers pass "" rather than building dynamic SQL.
type ListSignalsOpts struct {
	DeviceID   string
	SignalType string
	Limit      int
	Offset     int
}

// ListSignals returns the most recently captured signals matching the given
// filters, newest first, for the admin observation viewer.
func (p *Postgres) ListSignals(ctx context.Context, opts ListSignalsOpts) ([]SignalRow, error) {
	rows, err := p.Pool.Query(ctx, `
		SELECT id, device_id, captured_at, signal_type, lat, lon, payload
		FROM signals
		WHERE ($1 = '' OR device_id = $1::uuid)
		  AND ($2 = '' OR signal_type = $2)
		ORDER BY captured_at DESC
		LIMIT $3 OFFSET $4`,
		opts.DeviceID, opts.SignalType, opts.Limit, opts.Offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	signals := make([]SignalRow, 0, opts.Limit)
	for rows.Next() {
		var s SignalRow
		if err := rows.Scan(&s.ID, &s.DeviceID, &s.CapturedAt, &s.SignalType, &s.Lat, &s.Lon, &s.Payload); err != nil {
			return nil, err
		}
		signals = append(signals, s)
	}
	return signals, rows.Err()
}

// HeatmapPoint is a grid cell of observation density for the admin heat map.
type HeatmapPoint struct {
	Lat   float64 `json:"lat"`
	Lon   float64 `json:"lon"`
	Count int     `json:"count"`
}

// HeatmapOpts filters HeatmapPoints. Precision is the number of decimal
// places lat/lon are rounded to before grouping -- e.g. 3 (~110m cells) is a
// reasonable default; callers pass "" for DeviceID/SignalType to mean
// "no filter".
type HeatmapOpts struct {
	DeviceID   string
	SignalType string
	Precision  int
}

// HeatmapPoints returns observation counts grouped into a lat/lon grid, for
// rendering as a density heat map. Only signals with a location are
// included.
func (p *Postgres) HeatmapPoints(ctx context.Context, opts HeatmapOpts) ([]HeatmapPoint, error) {
	rows, err := p.Pool.Query(ctx, `
		SELECT round(lat::numeric, $1)::float8 AS grid_lat,
		       round(lon::numeric, $1)::float8 AS grid_lon,
		       count(*)
		FROM signals
		WHERE lat IS NOT NULL AND lon IS NOT NULL
		  AND ($2 = '' OR device_id = $2::uuid)
		  AND ($3 = '' OR signal_type = $3)
		GROUP BY grid_lat, grid_lon
		ORDER BY count(*) DESC`,
		opts.Precision, opts.DeviceID, opts.SignalType,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	points := make([]HeatmapPoint, 0)
	for rows.Next() {
		var pt HeatmapPoint
		if err := rows.Scan(&pt.Lat, &pt.Lon, &pt.Count); err != nil {
			return nil, err
		}
		points = append(points, pt)
	}
	return points, rows.Err()
}

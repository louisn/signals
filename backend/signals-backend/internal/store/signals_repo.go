package store

import (
	"context"

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

CREATE TABLE devices (
    id            UUID PRIMARY KEY,
    api_key_hash  TEXT NOT NULL UNIQUE,
    label         TEXT,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ,
    app_version   TEXT,
    os_version    TEXT,
    disabled      BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE upload_batches (
    id             UUID PRIMARY KEY,
    device_id      UUID NOT NULL REFERENCES devices(id),
    received_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    record_count   INT NOT NULL,
    accepted_count INT NOT NULL,
    rejected_count INT NOT NULL
);

CREATE TABLE signals (
    id                     UUID NOT NULL,
    device_id              UUID NOT NULL REFERENCES devices(id),
    captured_at            TIMESTAMPTZ NOT NULL,
    received_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    signal_type            TEXT NOT NULL,
    lat                    DOUBLE PRECISION,
    lon                    DOUBLE PRECISION,
    horizontal_accuracy_m  DOUBLE PRECISION,
    location_age_s         DOUBLE PRECISION,
    payload                JSONB NOT NULL,
    batch_id               UUID NOT NULL,
    PRIMARY KEY (id, captured_at)
) PARTITION BY RANGE (captured_at);

-- A default catch-all partition; monthly partitions should be created ahead of
-- traffic by an ops script (see docs/architecture.md) once real volume exists.
CREATE TABLE signals_default PARTITION OF signals DEFAULT;

CREATE INDEX idx_signals_device_captured ON signals (device_id, captured_at);
CREATE INDEX idx_signals_type_captured ON signals (signal_type, captured_at);

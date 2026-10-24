-- =============================================================
-- 10-master-schema.sql
-- Master DB schema for multi-tenant routing.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -------------------------------------------------------------
-- 1. Clients
-- -------------------------------------------------------------
CREATE TABLE clients (
    client_id           UUID PRIMARY KEY,
    client_name         TEXT NOT NULL,
    admin_email         TEXT NOT NULL,
    db_connect_string   TEXT,
    gemini_api_key      TEXT,
    allowed_origins     TEXT,
    brand_color         TEXT DEFAULT '#2BB673',
    status              TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'suspended', 'trial')),
    start_date          DATE NOT NULL DEFAULT '1900-01-01',
    end_date            DATE NOT NULL DEFAULT '9999-12-31',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);

-- -------------------------------------------------------------
-- 2. Instances
-- -------------------------------------------------------------
CREATE TABLE instances (
    instance_id         UUID PRIMARY KEY,
    client_id           UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    instance_type       TEXT NOT NULL CHECK (instance_type IN ('public', 'internal')),
    db_connect_string   TEXT,
    gemini_api_key      TEXT,
    brand_color         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX instances_client_id_idx ON instances (client_id);

-- -------------------------------------------------------------
-- 3. Tenant Usage Log
-- -------------------------------------------------------------
CREATE TABLE tenant_usage_log (
    log_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    instance_id     UUID NOT NULL REFERENCES instances(instance_id) ON DELETE CASCADE,
    question_length INT NOT NULL,
    status          TEXT NOT NULL,
    chunks_found    INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX tenant_usage_date_idx ON tenant_usage_log (created_at DESC);

-- -------------------------------------------------------------
-- 4. Auto-update changed_at
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_changed_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.changed_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER clients_changed_at
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION set_changed_at();

CREATE TRIGGER instances_changed_at
    BEFORE UPDATE ON instances
    FOR EACH ROW EXECUTE FUNCTION set_changed_at();

-- -------------------------------------------------------------
-- 5. Flattened view
-- -------------------------------------------------------------
CREATE VIEW v_tenant_config AS
SELECT
    i.instance_id,
    i.instance_type,
    c.client_id,
    c.client_name,
    COALESCE(i.db_connect_string, c.db_connect_string) AS db_connect_string,
    COALESCE(i.gemini_api_key, c.gemini_api_key)       AS gemini_api_key,
    COALESCE(i.brand_color, c.brand_color)             AS brand_color,
    c.allowed_origins,
    c.status
FROM instances i
JOIN clients c ON c.client_id = i.client_id
WHERE c.status IN ('active', 'trial')
  AND CURRENT_DATE BETWEEN c.start_date AND c.end_date;

-- -------------------------------------------------------------
-- 6. Settings (moved here from RAG — one shared copy)
-- -------------------------------------------------------------
CREATE TABLE settings (
    setting_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    setting_key    TEXT NOT NULL UNIQUE,
    setting_value  NUMERIC(10,4) NOT NULL,
    setting_type   TEXT NOT NULL DEFAULT 'number'
                   CHECK (setting_type IN ('number','boolean','integer')),
    description    TEXT,
    start_date     DATE NOT NULL DEFAULT '1900-01-01',
    end_date       DATE NOT NULL DEFAULT '9999-12-31',
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX settings_active_idx ON settings (start_date, end_date);

CREATE VIEW active_settings AS
SELECT * FROM settings
WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;

COMMIT;
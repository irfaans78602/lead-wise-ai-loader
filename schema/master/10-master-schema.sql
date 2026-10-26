-- =============================================================
-- 10-master-schema.sql
-- Master DB schema for multi-tenant routing and tier management.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -------------------------------------------------------------
-- 1. Tiers (Defines your 10 commercial plans)
-- -------------------------------------------------------------
CREATE TABLE tiers (
    tier_id             TEXT PRIMARY KEY, 
    display_name        TEXT NOT NULL,
    max_embeddings      INTEGER NOT NULL,
    max_storage_mb      INTEGER NOT NULL,
    neon_compute_size   TEXT NOT NULL,     -- Maps to Neon's CU sizes
    monthly_base_fee    NUMERIC(10, 2) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed the 10 tiers you outlined
INSERT INTO tiers (tier_id, display_name, max_embeddings, max_storage_mb, neon_compute_size, monthly_base_fee) VALUES
('nano',            'Nano',            10000,     1024,  'CU_0.25', 0.00),
('micro',           'Micro',           25000,     2048,  'CU_0.25', 0.00),
('starter',         'Starter',         50000,     4096,  'CU_0.5',  19.00),
('basic',           'Basic',           100000,    8192,  'CU_0.5',  39.00),
('standard',        'Standard',        250000,    16384, 'CU_1',    79.00),
('growth',          'Growth',          500000,    32768, 'CU_1',    149.00),
('professional',    'Professional',    1000000,   65536, 'CU_2',    299.00),
('business',        'Business',        2500000,   131072,'CU_4',    599.00),
('enterprise',      'Enterprise',      5000000,   262144,'CU_8',    999.00),
('enterprise_plus', 'Enterprise Plus', 10000000,  524288,'CU_8',    1999.00)
ON CONFLICT DO NOTHING;

-- -------------------------------------------------------------
-- 2. Clients
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
-- 3. Client Subscriptions (Maps clients to tiers & tracks Neon)
-- -------------------------------------------------------------
CREATE TABLE client_subscriptions (
    client_id           UUID PRIMARY KEY REFERENCES clients(client_id) ON DELETE CASCADE,
    tier_id             TEXT NOT NULL REFERENCES tiers(tier_id),
    neon_project_id     TEXT,
    current_embeddings  INTEGER NOT NULL DEFAULT 0,
    subscription_status TEXT NOT NULL DEFAULT 'active' CHECK (subscription_status IN ('active', 'past_due', 'canceled')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------
-- 4. Instances
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
-- 5. Tenant Usage Log
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
-- 6. Auto-update changed_at
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

CREATE TRIGGER subscriptions_changed_at
    BEFORE UPDATE ON client_subscriptions
    FOR EACH ROW EXECUTE FUNCTION set_changed_at();

-- -------------------------------------------------------------
-- 7. Flattened view (Now includes Tier limits)
-- -------------------------------------------------------------
-- Keyed by instance_id: one row per (client, instance_type).
-- Use this when you need per-instance data (which Ask AI instance,
-- which db_connect_string override, which gemini_api_key override).
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
    c.status,
    
    -- ADDED: Tier constraints for automatic validation
    s.tier_id,
    t.display_name                                     AS tier_name,
    t.max_embeddings,
    s.current_embeddings
FROM instances i
JOIN clients c ON c.client_id = i.client_id
LEFT JOIN client_subscriptions s ON s.client_id = c.client_id
LEFT JOIN tiers t ON t.tier_id = s.tier_id
WHERE c.status IN ('active', 'trial')
  AND CURRENT_DATE BETWEEN c.start_date AND c.end_date;

-- -------------------------------------------------------------
-- 7b. Active clients (client-level)
-- -------------------------------------------------------------
-- Companion to v_tenant_config. Where v_tenant_config is keyed by
-- instance_id (one row per instance per client), active_clients is
-- keyed by client_id (one row per client).
--
-- Use this when you need "which clients are live right now" without
-- caring which instances they have. The test harness at /test_chats
-- uses this view to populate its client dropdown.
--
-- LEFT JOINs on client_subscriptions and tiers so a client with no
-- subscription (e.g. a pilot client mid-onboarding, or the platform
-- owner) still appears, with NULL tier info. Change to INNER JOINs
-- if you want to hide those.
--
-- This view is NOT the same as the tenant-side `active_clients`
-- view (which lives in the tenant DB and has different columns:
-- allowed_origins, email_to, country_id, segment_id, etc.).
-- Same name, different DB, different purpose. Do not merge them.
CREATE VIEW active_clients AS
SELECT
    c.client_id,
    c.client_name,
    c.admin_email,
    c.db_connect_string,
    c.gemini_api_key,
    c.allowed_origins,
    c.brand_color,
    c.status,
    c.start_date,
    c.end_date,
    c.created_at,
    c.changed_at,
    s.tier_id,
    t.display_name       AS tier_name,
    t.max_embeddings,
    t.max_storage_mb,
    s.current_embeddings,
    s.subscription_status
FROM clients c
LEFT JOIN client_subscriptions s ON s.client_id = c.client_id
LEFT JOIN tiers t ON t.tier_id = s.tier_id
WHERE c.status IN ('active', 'trial')
  AND CURRENT_DATE BETWEEN c.start_date AND c.end_date;

-- -------------------------------------------------------------
-- 8. Settings
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
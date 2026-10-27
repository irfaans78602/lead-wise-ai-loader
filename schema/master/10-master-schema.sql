-- =============================================================
-- 10-master-schema.sql
-- Master DB schema for multi-tenant routing, branding, and settings.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -------------------------------------------------------------
-- 1. Tiers
-- -------------------------------------------------------------
CREATE TABLE tiers (
    tier_id             TEXT PRIMARY KEY, 
    display_name        TEXT NOT NULL,
    max_embeddings      INTEGER NOT NULL,
    max_storage_mb      INTEGER NOT NULL,
    neon_compute_size   TEXT NOT NULL,
    monthly_base_fee    NUMERIC(10, 2) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

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
-- 2. Clients (Routing & Identity)
-- -------------------------------------------------------------
CREATE TABLE clients (
    client_id           UUID PRIMARY KEY,
    client_name         TEXT NOT NULL,
    admin_email         TEXT NOT NULL,
    db_connect_string   TEXT,
    gemini_api_key      TEXT,
    allowed_origins     TEXT,
    status              TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'suspended', 'trial')),
    start_date          DATE NOT NULL DEFAULT '1900-01-01',
    end_date            DATE NOT NULL DEFAULT '9999-12-31',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);

-- -------------------------------------------------------------
-- 3. Client Brandings (1:1 with Clients)
-- -------------------------------------------------------------
CREATE TABLE client_brandings (
    client_id           UUID PRIMARY KEY REFERENCES clients(client_id) ON DELETE CASCADE,
    
    -- Identity
    display_name        TEXT NOT NULL,
    support_email       TEXT,
    support_url         TEXT CHECK (support_url IS NULL OR support_url LIKE 'https://%'),

    -- Colours
    primary_color       TEXT NOT NULL DEFAULT '#0f766e' CHECK (primary_color ~ '^#[0-9a-fA-F]{6}$'),
    primary_contrast    TEXT CHECK (primary_contrast IS NULL OR primary_contrast ~ '^#[0-9a-fA-F]{6}$'),
    secondary_color     TEXT CHECK (secondary_color IS NULL OR secondary_color ~ '^#[0-9a-fA-F]{6}$'),
    accent_color        TEXT CHECK (accent_color IS NULL OR accent_color ~ '^#[0-9a-fA-F]{6}$'),
    bg_color            TEXT NOT NULL DEFAULT '#ffffff' CHECK (bg_color ~ '^#[0-9a-fA-F]{6}$'),
    surface_color       TEXT CHECK (surface_color IS NULL OR surface_color ~ '^#[0-9a-fA-F]{6}$'),
    text_color          TEXT NOT NULL DEFAULT '#111827' CHECK (text_color ~ '^#[0-9a-fA-F]{6}$'),
    text_muted_color    TEXT CHECK (text_muted_color IS NULL OR text_muted_color ~ '^#[0-9a-fA-F]{6}$'),
    border_color        TEXT CHECK (border_color IS NULL OR border_color ~ '^#[0-9a-fA-F]{6}$'),

    -- Typography
    radius_px           INTEGER NOT NULL DEFAULT 12 CHECK (radius_px >= 0 AND radius_px <= 24),
    font_family         TEXT NOT NULL DEFAULT 'inter',
    density             TEXT CHECK (density IN ('compact', 'comfortable', 'spacious')),
    dark_mode           TEXT NOT NULL DEFAULT 'auto' CHECK (dark_mode IN ('on', 'off', 'auto')),

    -- Logo assets
    logo_light_svg      TEXT,
    logo_dark_svg       TEXT,
    favicon_svg         TEXT,
    logo_light_alt      TEXT,
    logo_dark_alt       TEXT,
    logo_version        INTEGER NOT NULL DEFAULT 1,
    logo_updated_at     TIMESTAMPTZ,

    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------
-- 4. Client Texts
-- -------------------------------------------------------------
CREATE TABLE client_texts (
    client_id      UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    channel        TEXT NOT NULL CHECK (channel IN ('ask_ai', 'live_chat')),
    locale         VARCHAR(15) NOT NULL DEFAULT 'en',
    text_key       TEXT NOT NULL,
    text_value     TEXT NOT NULL,
    start_date     DATE NOT NULL DEFAULT '1900-01-01',
    end_date       DATE NOT NULL DEFAULT '9999-12-31',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (client_id, channel, locale, text_key, start_date),
    CHECK (start_date <= end_date)
);

CREATE INDEX client_texts_lookup_idx ON client_texts (client_id, channel, locale) WHERE end_date = '9999-12-31';
CREATE UNIQUE INDEX client_texts_current_unique ON client_texts (client_id, channel, locale, text_key) WHERE end_date = '9999-12-31';

CREATE VIEW v_client_texts AS
SELECT
    client_id,
    channel,
    locale,
    jsonb_object_agg(text_key, text_value) AS texts
FROM client_texts
WHERE end_date = '9999-12-31'
GROUP BY client_id, channel, locale;

-- -------------------------------------------------------------
-- 5. Client Subscriptions
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
-- 6. Instances
-- -------------------------------------------------------------
CREATE TABLE instances (
    instance_id         UUID PRIMARY KEY,
    client_id           UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    instance_type       TEXT NOT NULL CHECK (instance_type IN ('public', 'internal')),
    db_connect_string   TEXT,
    gemini_api_key      TEXT,
    start_date          DATE NOT NULL DEFAULT '1900-01-01',
    end_date            DATE NOT NULL DEFAULT '9999-12-31',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX instances_client_id_idx ON instances (client_id);
CREATE INDEX instances_active_idx ON instances (start_date, end_date);

-- -------------------------------------------------------------
-- 7. Settings & Logs
-- -------------------------------------------------------------
CREATE TABLE settings (
    setting_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    setting_key    TEXT NOT NULL UNIQUE,
    setting_value  TEXT NOT NULL,
    setting_type   TEXT NOT NULL DEFAULT 'number' CHECK (setting_type IN ('number','boolean','integer','string')),
    description    TEXT,
    start_date     DATE NOT NULL DEFAULT '1900-01-01',
    end_date       DATE NOT NULL DEFAULT '9999-12-31',
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX settings_active_idx ON settings (start_date, end_date);
CREATE UNIQUE INDEX settings_key_active_idx ON settings (setting_key) WHERE end_date = '9999-12-31';

CREATE VIEW active_settings AS SELECT * FROM settings WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;

CREATE TABLE tenant_usage_log (
    log_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    instance_id     UUID NOT NULL REFERENCES instances(instance_id) ON DELETE CASCADE,
    question_length INT NOT NULL,
    status          TEXT NOT NULL,
    chunks_found    INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------
-- 8. Auto-update changed_at
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_changed_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.changed_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER clients_changed_at BEFORE UPDATE ON clients FOR EACH ROW EXECUTE FUNCTION set_changed_at();
CREATE TRIGGER instances_changed_at BEFORE UPDATE ON instances FOR EACH ROW EXECUTE FUNCTION set_changed_at();
CREATE TRIGGER subscriptions_changed_at BEFORE UPDATE ON client_subscriptions FOR EACH ROW EXECUTE FUNCTION set_changed_at();
CREATE TRIGGER settings_changed_at BEFORE UPDATE ON settings FOR EACH ROW EXECUTE FUNCTION set_changed_at();
CREATE TRIGGER brandings_changed_at BEFORE UPDATE ON client_brandings FOR EACH ROW EXECUTE FUNCTION set_changed_at();

-- -------------------------------------------------------------
-- 9. Flattened Views
-- -------------------------------------------------------------
CREATE VIEW v_client_connections AS
SELECT
    c.client_id,
    i.instance_id,
    i.instance_type,
    COALESCE(i.db_connect_string, c.db_connect_string) AS db_connect_string
FROM clients c
LEFT JOIN instances i 
       ON i.client_id = c.client_id 
      AND CURRENT_DATE BETWEEN i.start_date AND i.end_date
WHERE c.status IN ('active', 'trial')
  AND CURRENT_DATE BETWEEN c.start_date AND c.end_date;

CREATE VIEW v_tenant_config AS
SELECT
    i.instance_id,
    i.instance_type,
    c.client_id,
    c.client_name,
    COALESCE(i.db_connect_string, c.db_connect_string) AS db_connect_string,
    COALESCE(i.gemini_api_key, c.gemini_api_key)       AS gemini_api_key,
    c.allowed_origins,
    c.status,
    s.tier_id,
    t.display_name                                     AS tier_name,
    t.max_embeddings,
    s.current_embeddings
FROM instances i
JOIN clients c ON c.client_id = i.client_id
LEFT JOIN client_subscriptions s ON s.client_id = c.client_id
LEFT JOIN tiers t ON t.tier_id = s.tier_id
WHERE c.status IN ('active', 'trial')
  AND CURRENT_DATE BETWEEN c.start_date AND c.end_date
  AND CURRENT_DATE BETWEEN i.start_date AND i.end_date;

CREATE VIEW active_clients AS
SELECT
    c.client_id,
    c.client_name,
    c.admin_email,
    c.db_connect_string,
    c.gemini_api_key,
    c.allowed_origins,
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

COMMIT;
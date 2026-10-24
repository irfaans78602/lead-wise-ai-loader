-- =============================================================
-- 10-rag-schema.sql
-- Ask AI / RAG Backend. Postgres 14+.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================
-- 1. Clients
-- =============================================================
CREATE TABLE clients (
    client_id           UUID PRIMARY KEY,
    status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'archived')),
    chat_enabled        BOOLEAN NOT NULL DEFAULT true,
    display_name        TEXT NOT NULL,
    title               TEXT,
    description         TEXT,
    greeting            TEXT NOT NULL DEFAULT 'Hi! How can we help you today?',
    placeholder         TEXT NOT NULL DEFAULT 'Ask a question…',
    disclaimer          TEXT,
    support_email       TEXT,
    support_url         TEXT CHECK (support_url IS NULL OR support_url LIKE 'https://%'),
    primary_color       TEXT NOT NULL DEFAULT '#0f766e' CHECK (primary_color ~ '^#[0-9a-fA-F]{6}$'),
    primary_contrast    TEXT CHECK (primary_contrast IS NULL OR primary_contrast ~ '^#[0-9a-fA-F]{6}$'),
    secondary_color     TEXT CHECK (secondary_color IS NULL OR secondary_color ~ '^#[0-9a-fA-F]{6}$'),
    accent_color        TEXT CHECK (accent_color IS NULL OR accent_color ~ '^#[0-9a-fA-F]{6}$'),
    bg_color            TEXT NOT NULL DEFAULT '#ffffff' CHECK (bg_color ~ '^#[0-9a-fA-F]{6}$'),
    surface_color       TEXT CHECK (surface_color IS NULL OR surface_color ~ '^#[0-9a-fA-F]{6}$'),
    text_color          TEXT NOT NULL DEFAULT '#111827' CHECK (text_color ~ '^#[0-9a-fA-F]{6}$'),
    text_muted_color    TEXT CHECK (text_muted_color IS NULL OR text_muted_color ~ '^#[0-9a-fA-F]{6}$'),
    border_color        TEXT CHECK (border_color IS NULL OR border_color ~ '^#[0-9a-fA-F]{6}$'),
    radius_px           INTEGER NOT NULL DEFAULT 12 CHECK (radius_px >= 0 AND radius_px <= 24),
    font_family         TEXT NOT NULL DEFAULT 'inter',
    density             TEXT CHECK (density IN ('compact', 'comfortable', 'spacious')),
    dark_mode           TEXT NOT NULL DEFAULT 'auto' CHECK (dark_mode IN ('on', 'off', 'auto')),
    logo_light_svg      TEXT NOT NULL,
    logo_dark_svg       TEXT,
    favicon_svg         TEXT,
    logo_light_alt      TEXT,
    logo_dark_alt       TEXT,
    logo_version        INTEGER NOT NULL DEFAULT 1,
    logo_updated_at     TIMESTAMPTZ,
    allowed_origins     TEXT NOT NULL DEFAULT '',
    scope               TEXT NOT NULL DEFAULT 'public' CHECK (scope IN ('public', 'internal')),
    retention_days      INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE VIEW v_tenant_config AS
SELECT
    client_id,
    scope AS instance_type,
    allowed_origins,
    primary_color AS brand_color
FROM clients
WHERE status = 'active';

-- =============================================================
-- 2. Ask AI — RAG CONTENT (VECTOR STORE)
-- =============================================================
CREATE TABLE site_content (
    id              BIGSERIAL PRIMARY KEY,
    client_id       UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    locale          VARCHAR(15) NOT NULL,
    scope           VARCHAR(20) NOT NULL DEFAULT 'public'
                    CHECK (scope IN ('public', 'internal')),
    section_path    TEXT,
    source          TEXT NOT NULL,
    chunk_text      TEXT NOT NULL,
    embedding       VECTOR(768),
    start_date      DATE NOT NULL DEFAULT '1900-01-01',
    end_date        DATE NOT NULL DEFAULT '9999-12-31',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON site_content USING hnsw (embedding vector_cosine_ops);
CREATE INDEX site_content_client_idx  ON site_content (client_id);
CREATE INDEX site_content_scope_idx   ON site_content (scope);
CREATE INDEX site_content_section_idx ON site_content (section_path);
CREATE INDEX site_content_locale_idx  ON site_content (locale);

-- =============================================================
-- 3. Ask AI — RUNTIME LOG
-- =============================================================
CREATE TABLE ask_ai_log (
    ask_ai_log_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    submission_id   UUID NOT NULL UNIQUE,
    client_id       UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    session_id      UUID,
    question        TEXT NOT NULL,
    answer          TEXT NOT NULL,
    locale          VARCHAR(5),
    ip_hash         TEXT,
    user_agent      TEXT,
    referer         TEXT,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          TEXT NOT NULL DEFAULT 'success'
                    CHECK (status IN ('success', 'db_error', 'embed_error', 'embed_error_quota', 'gen_error', 'unanswered', 'no_context', 'notified', 'resolved')),
    chunks_found    INTEGER NOT NULL DEFAULT 0,
    utm_source      VARCHAR(100),
    utm_medium      VARCHAR(100),
    utm_campaign    VARCHAR(100)
);

CREATE INDEX ask_ai_log_client_idx    ON ask_ai_log (client_id, submitted_at DESC);
CREATE INDEX ask_ai_log_submitted_idx ON ask_ai_log (submitted_at DESC);
CREATE INDEX ask_ai_log_locale_idx    ON ask_ai_log (locale, submitted_at DESC);
CREATE INDEX ask_ai_log_ip_hash_idx   ON ask_ai_log (ip_hash) WHERE ip_hash IS NOT NULL;
CREATE INDEX ask_ai_log_session_idx   ON ask_ai_log (session_id, submitted_at ASC);

-- =============================================================
-- 4. Ask AI Gap Analysis View
-- =============================================================
CREATE OR REPLACE VIEW v_ask_ai_gaps AS
SELECT
    client_id,
    question,
    count(*) as times_asked,
    array_agg(DISTINCT status) as error_types,
    max(submitted_at) as last_asked
FROM ask_ai_log
WHERE status IN ('unanswered', 'no_context')
GROUP BY client_id, question
ORDER BY times_asked DESC;

COMMIT;
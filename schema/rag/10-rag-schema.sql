-- =============================================================
-- 10-rag-schema.sql
-- Ask AI / RAG Backend. Postgres 14+.
-- English only for now; client_texts.locale defaults to 'en'.
-- Unified chatbots_logs table for both Ask AI and Live Chat.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================
-- 1. Clients
-- =============================================================
CREATE TABLE clients (
    client_id           UUID PRIMARY KEY,
    status              TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'suspended', 'archived')),
    chat_enabled        BOOLEAN NOT NULL DEFAULT true,

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

    -- Policy
    allowed_origins     TEXT NOT NULL DEFAULT '',
    scope               TEXT NOT NULL DEFAULT 'public' CHECK (scope IN ('public', 'internal')),
    retention_days      INTEGER,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Route helper for ask_ai.py — instance_id keyed.
CREATE VIEW v_tenant_config AS
SELECT
    client_id,
    scope AS instance_type,
    allowed_origins,
    primary_color AS brand_color
FROM clients
WHERE status = 'active';

-- =============================================================
-- 2. Client Texts
-- =============================================================
CREATE TABLE client_texts (
    client_id      UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    channel        TEXT NOT NULL
                   CHECK (channel IN ('ask_ai', 'live_chat')),
    locale         VARCHAR(15) NOT NULL DEFAULT 'en',
    text_key       TEXT NOT NULL
                   CHECK (text_key IN (
                       'title', 'description', 'greeting', 'placeholder', 'disclaimer',
                       'thinking', 'waking_up', 'send', 'new_chat',
                       'maximize', 'minimize', 'close',
                       'legal_pre', 'legal_link', 'legal_post',
                       'start_button', 'restart_button',
                       'connecting', 'empty_state', 'empty_conversation',
                       'error_generic', 'error_network', 'error_timeout',
                       'error_rate_limited', 'error_invalid_id', 'error_closed',
                       'error_no_question', 'close_confirmation',
                       'privacy_url', 'support_link', 'back_link',
                       'ai_badge', 'powered_by'
                   )),
    text_value     TEXT NOT NULL,
    start_date     DATE NOT NULL DEFAULT '1900-01-01',
    end_date       DATE NOT NULL DEFAULT '9999-12-31',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (client_id, channel, locale, text_key, start_date),
    CHECK (start_date <= end_date)
);

CREATE INDEX client_texts_lookup_idx
    ON client_texts (client_id, channel, locale)
    WHERE end_date = '9999-12-31';

CREATE INDEX client_texts_key_idx
    ON client_texts (client_id, channel, locale, text_key)
    WHERE end_date = '9999-12-31';

-- Expose the current copy as nested JSON.
CREATE VIEW v_client_texts AS
SELECT
    client_id,
    channel,
    locale,
    jsonb_object_agg(text_key, text_value) AS texts
FROM client_texts
WHERE end_date = '9999-12-31'
GROUP BY client_id, channel, locale;

-- =============================================================
-- 3. Ask AI — RAG CONTENT (VECTOR STORE)
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
-- 4. Ask AI Logs
-- =============================================================
CREATE TABLE ask_ai_logs (
    log_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id       UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    session_id      TEXT,
    question        TEXT NOT NULL,
    answer          TEXT NOT NULL,
    locale          VARCHAR(5),
    ip_hash         TEXT,
    user_agent      TEXT,
    referer         TEXT,
    status          TEXT NOT NULL DEFAULT 'success',
    chunks_found    INTEGER NOT NULL DEFAULT 0,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ask_ai_logs_client_idx ON ask_ai_logs (client_id, submitted_at DESC);
CREATE INDEX ask_ai_logs_ip_idx ON ask_ai_logs (ip_hash, submitted_at DESC) WHERE ip_hash IS NOT NULL;
CREATE INDEX ask_ai_logs_session_idx ON ask_ai_logs (session_id, submitted_at ASC) WHERE session_id IS NOT NULL;

-- =============================================================
-- 5. Ask AI Gap Analysis View
-- =============================================================
CREATE OR REPLACE VIEW v_ask_ai_gaps AS
SELECT
    client_id,
    question,
    count(*) AS times_asked,
    array_agg(DISTINCT status) AS error_types,
    max(submitted_at) AS last_asked
FROM ask_ai_logs
WHERE status IN ('unanswered', 'no_context')
GROUP BY client_id, question
ORDER BY times_asked DESC;

COMMIT;
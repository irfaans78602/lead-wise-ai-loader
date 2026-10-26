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
-- Branding, identity, and policy. Per-channel copy lives in
-- client_texts (section 2), not here. That keeps this table
-- stable when copy changes, and lets each channel carry its
-- own title/greeting/placeholder.
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
-- Per-channel, per-locale copy. One row per (client, channel,
-- locale, key, version). The "current" row is end_date =
-- '9999-12-31'. Adding a new key is a data change, not a schema
-- change. Adding a new locale is a data change too.
--
-- Channels: 'ask_ai' and 'live_chat'. If you add a third channel
-- later, add it to the CHECK and to the frontend's runtime
-- groups, not to this table's shape.
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

-- Expose the current copy as nested JSON:
--   { ask_ai: { en: { title: "...", greeting: "..." } }, live_chat: { en: {...} } }
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
-- 4. Unified Chatbots Log (Ask AI + Live Chat)
-- =============================================================
-- One row per interaction (question or /start), for both channels.
-- channel distinguishes; status vocabulary is enforced per channel.
--
-- Ask AI:  uses chunks_found; leaves utm_*/section_path/ad_id NULL.
-- Live Chat: uses utm_*/section_path/ad_id; leaves chunks_found = 0.
--
-- ad_id is the Live Chat ad (73-char combined id's suffix). It's
-- NULL for Ask AI, which has no ad campaign. The Live Chat
-- analytics views (funnel, dropoff) group by (client_id, ad_id)
-- so a client with multiple locales can see per-locale behaviour.
CREATE TABLE chatbots_logs (
    log_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    submission_id   UUID NOT NULL UNIQUE,
    client_id       UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    channel         TEXT NOT NULL CHECK (channel IN ('ask_ai', 'live_chat')),
    ad_id           UUID,                                    -- Live Chat only

    session_id      TEXT,
    question        TEXT NOT NULL,
    answer          TEXT NOT NULL,
    locale          VARCHAR(5),

    ip_hash         TEXT,
    user_agent      TEXT,
    referer         TEXT,

    status          TEXT NOT NULL DEFAULT 'success',
    chunks_found    INTEGER NOT NULL DEFAULT 0,

    utm_source      VARCHAR(100),
    utm_medium      VARCHAR(100),
    utm_campaign    VARCHAR(100),
    section_path    TEXT,

    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CHECK (
        (channel = 'ask_ai' AND status IN (
            'success', 'start', 'no_context', 'unanswered',
            'gen_error', 'db_error', 'embed_error', 'embed_error_quota',
            'notified', 'resolved'
        ))
        OR
        (channel = 'live_chat' AND status IN (
            'success', 'start', 'completed', 'abandoned', 'error'
        ))
    ),

    -- ad_id is only meaningful for Live Chat.
    CHECK (channel = 'live_chat' OR ad_id IS NULL)
);

CREATE INDEX chatbots_logs_client_channel_idx
    ON chatbots_logs (client_id, channel, submitted_at DESC);

CREATE INDEX chatbots_logs_submitted_idx
    ON chatbots_logs (submitted_at DESC);

CREATE INDEX chatbots_logs_channel_ip_idx
    ON chatbots_logs (channel, ip_hash, submitted_at DESC)
    WHERE ip_hash IS NOT NULL;

CREATE INDEX chatbots_logs_channel_status_idx
    ON chatbots_logs (channel, status, submitted_at DESC);

CREATE INDEX chatbots_logs_session_idx
    ON chatbots_logs (channel, session_id, submitted_at ASC)
    WHERE session_id IS NOT NULL;

CREATE INDEX chatbots_logs_ad_channel_idx
    ON chatbots_logs (ad_id, channel, submitted_at DESC)
    WHERE ad_id IS NOT NULL;

-- =============================================================
-- 5. Ask AI Gap Analysis View
-- =============================================================
-- "Which questions did the AI fail to answer?"
-- Groups by question text (not by position), because Ask AI is
-- a retrieval engine — a gap means the RAG corpus is missing a
-- chunk for that topic. Content-gap analysis.
CREATE OR REPLACE VIEW v_ask_ai_gaps AS
SELECT
    client_id,
    question,
    count(*) AS times_asked,
    array_agg(DISTINCT status) AS error_types,
    max(submitted_at) AS last_asked
FROM chatbots_logs
WHERE channel = 'ask_ai'
  AND status IN ('unanswered', 'no_context')
GROUP BY client_id, question
ORDER BY times_asked DESC;

-- =============================================================
-- 6. Live Chat Funnel View
-- =============================================================
-- Coarse daily funnel: how many starts/successes/completions/
-- abandons per day, per client, per ad.
CREATE OR REPLACE VIEW v_live_chat_funnel AS
SELECT
    client_id,
    ad_id,
    date_trunc('day', submitted_at)::date AS day,
    status,
    count(*) AS messages
FROM chatbots_logs
WHERE channel = 'live_chat'
GROUP BY client_id, ad_id, day, status;

-- =============================================================
-- 7. Live Chat Drop-Off View
-- =============================================================
-- "What fraction of Live Chat traffic is each status?"
-- Rolling 30-day window, grouped by (client_id, ad_id, status).
-- This is the Live Chat equivalent of v_ask_ai_gaps, but the
-- question it answers is different: not "what content is
-- missing" but "where in the flow are we losing people".
--
-- High abandoned % on a specific ad → that ad's qualification
-- flow has a cliff (bad question, unclear wording, too long).
-- High error % → something is technically broken for that ad.
-- High completed % → the flow is converting.
CREATE OR REPLACE VIEW v_live_chat_dropoff AS
WITH per_ad AS (
    SELECT
        client_id,
        ad_id,
        status,
        count(*) AS n
    FROM chatbots_logs
    WHERE channel = 'live_chat'
      AND submitted_at > now() - interval '30 days'
    GROUP BY client_id, ad_id, status
)
SELECT
    client_id,
    ad_id,
    status,
    n,
    round(
        100.0 * n / nullif(sum(n) OVER (PARTITION BY client_id, ad_id), 0),
        1
    ) AS pct
FROM per_ad
ORDER BY client_id, ad_id, n DESC;

COMMIT;
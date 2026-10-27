-- =============================================================
-- 10-rag-schema.sql
-- Ask AI / RAG Backend. Postgres 14+.
-- Assumes 1 database per client/tenant. No client_id needed.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================
-- 1. Ask AI — RAG CONTENT (VECTOR STORE)
-- =============================================================
CREATE TABLE site_content (
    id              BIGSERIAL PRIMARY KEY,
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
CREATE INDEX site_content_scope_idx   ON site_content (scope);
CREATE INDEX site_content_section_idx ON site_content (section_path);
CREATE INDEX site_content_locale_idx  ON site_content (locale);

-- =============================================================
-- 2. Ask AI Logs
-- =============================================================
CREATE TABLE ask_ai_logs (
    log_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
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

CREATE INDEX ask_ai_logs_ip_idx ON ask_ai_logs (ip_hash, submitted_at DESC) WHERE ip_hash IS NOT NULL;
CREATE INDEX ask_ai_logs_session_idx ON ask_ai_logs (session_id, submitted_at ASC) WHERE session_id IS NOT NULL;

-- =============================================================
-- 3. Ask AI Gap Analysis View
-- =============================================================
CREATE OR REPLACE VIEW v_ask_ai_gaps AS
SELECT
    question,
    count(*) AS times_asked,
    array_agg(DISTINCT status) AS error_types,
    max(submitted_at) AS last_asked
FROM ask_ai_logs
WHERE status IN ('unanswered', 'no_context')
GROUP BY question
ORDER BY times_asked DESC;

COMMIT;
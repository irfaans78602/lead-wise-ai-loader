-- =============================================================
-- 00-rag-drop.sql
-- Drops everything created by any version of 10-rag-schema.sql.
-- Covers both the old (ask_ai_log) and new (chatbots_logs,
-- client_texts, and the three analytics views) objects, so a
-- drop/rebuild cycle works from either starting state.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- Views first (they reference tables, drop before them)
-- -------------------------------------------------------------
DROP VIEW IF EXISTS v_live_chat_dropoff CASCADE;
DROP VIEW IF EXISTS v_live_chat_funnel  CASCADE;
DROP VIEW IF EXISTS v_ask_ai_gaps       CASCADE;
DROP VIEW IF EXISTS v_client_texts      CASCADE;
DROP VIEW IF EXISTS v_tenant_config     CASCADE;

-- -------------------------------------------------------------
-- Tables in reverse dependency order
-- All FK to clients, so they drop before it.
-- ask_ai_log is the old name for what is now chatbots_logs;
-- including it handles DBs built before the rename.
-- -------------------------------------------------------------
DROP TABLE IF EXISTS ask_ai_log    CASCADE;
DROP TABLE IF EXISTS chatbots_logs CASCADE;
DROP TABLE IF EXISTS site_content  CASCADE;
DROP TABLE IF EXISTS client_texts  CASCADE;
DROP TABLE IF EXISTS clients       CASCADE;

COMMIT;
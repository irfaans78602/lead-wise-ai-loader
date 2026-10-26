-- =============================================================
-- 00-rag-drop.sql
-- Drops everything created by 10-rag-schema.sql.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- Views first (they reference tables, drop before them)
-- -------------------------------------------------------------
DROP VIEW IF EXISTS v_ask_ai_gaps       CASCADE;
DROP VIEW IF EXISTS v_client_texts      CASCADE;
DROP VIEW IF EXISTS v_tenant_config     CASCADE;

-- -------------------------------------------------------------
-- Tables in reverse dependency order
-- All FK to clients, so they drop before it.
-- -------------------------------------------------------------
DROP TABLE IF EXISTS ask_ai_logs   CASCADE;
DROP TABLE IF EXISTS site_content  CASCADE;
DROP TABLE IF EXISTS client_texts  CASCADE;
DROP TABLE IF EXISTS clients       CASCADE;

COMMIT;
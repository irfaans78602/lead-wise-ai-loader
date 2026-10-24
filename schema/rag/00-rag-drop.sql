-- =============================================================
-- 00-rag-drop.sql
-- Drops everything created by 10-rag-schema.sql.
-- =============================================================

BEGIN;

DROP VIEW  IF EXISTS v_ask_ai_gaps   CASCADE;
DROP VIEW  IF EXISTS v_tenant_config CASCADE;

DROP TABLE IF EXISTS ask_ai_log   CASCADE;
DROP TABLE IF EXISTS site_content CASCADE;
DROP TABLE IF EXISTS clients      CASCADE;

COMMIT;
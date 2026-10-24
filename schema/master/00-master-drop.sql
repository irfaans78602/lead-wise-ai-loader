-- =============================================================
-- 00-master-drop.sql
-- Drops the Master DB routing tables, views, and triggers.
-- =============================================================

BEGIN;

DROP VIEW IF EXISTS active_settings   CASCADE;
DROP VIEW IF EXISTS v_tenant_config   CASCADE;

DROP TRIGGER IF EXISTS clients_changed_at   ON clients   CASCADE;
DROP TRIGGER IF EXISTS instances_changed_at ON instances CASCADE;

DROP FUNCTION IF EXISTS set_changed_at() CASCADE;

DROP TABLE IF EXISTS settings         CASCADE;
DROP TABLE IF EXISTS tenant_usage_log CASCADE;
DROP TABLE IF EXISTS instances        CASCADE;
DROP TABLE IF EXISTS clients          CASCADE;

COMMIT;
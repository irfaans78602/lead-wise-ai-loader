-- =============================================================
-- 00-master-drop.sql
-- Drops the Master DB routing tables, views, and triggers.
-- =============================================================

BEGIN;

DROP VIEW IF EXISTS v_client_texts      CASCADE;
DROP VIEW IF EXISTS v_client_connections CASCADE;
DROP VIEW IF EXISTS v_tenant_config     CASCADE;
DROP VIEW IF EXISTS active_clients      CASCADE;
DROP VIEW IF EXISTS active_settings     CASCADE;

DROP TRIGGER IF EXISTS clients_changed_at             ON clients              CASCADE;
DROP TRIGGER IF EXISTS instances_changed_at           ON instances            CASCADE;
DROP TRIGGER IF EXISTS subscriptions_changed_at       ON client_subscriptions CASCADE;
DROP TRIGGER IF EXISTS settings_changed_at            ON settings             CASCADE;

DROP FUNCTION IF EXISTS set_changed_at() CASCADE;

DROP TABLE IF EXISTS tenant_usage_log     CASCADE;
DROP TABLE IF EXISTS client_subscriptions CASCADE;
DROP TABLE IF EXISTS client_texts         CASCADE;
DROP TABLE IF EXISTS client_brandings     CASCADE;
DROP TABLE IF EXISTS instances            CASCADE;
DROP TABLE IF EXISTS clients              CASCADE;
DROP TABLE IF EXISTS tiers                CASCADE;
DROP TABLE IF EXISTS settings             CASCADE;

COMMIT;
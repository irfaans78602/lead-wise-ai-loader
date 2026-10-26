-- =============================================================
-- 00-master-drop.sql
-- Drops the Master DB routing tables, views, and triggers.
--
-- Drop order matters:
--   1. Views first (they reference tables; CASCADE handles dependents).
--   2. Triggers next (they reference tables; drop before tables to be tidy).
--   3. Function (no dependents after triggers are gone).
--   4. Tables in reverse dependency order:
--        tenant_usage_log    -> instances
--        client_subscriptions-> clients, tiers
--        instances           -> clients
--        clients             (no FKs to other master tables)
--        tiers               (referenced by client_subscriptions)
--        settings            (no FKs)
--
-- CASCADE on the DROPs means a partially-applied prior run still cleans up.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- 1. Views
-- -------------------------------------------------------------
DROP VIEW IF EXISTS active_clients      CASCADE;
DROP VIEW IF EXISTS active_settings     CASCADE;
DROP VIEW IF EXISTS v_tenant_config     CASCADE;

-- -------------------------------------------------------------
-- 2. Triggers
-- -------------------------------------------------------------
DROP TRIGGER IF EXISTS clients_changed_at             ON clients              CASCADE;
DROP TRIGGER IF EXISTS instances_changed_at           ON instances            CASCADE;
DROP TRIGGER IF EXISTS subscriptions_changed_at       ON client_subscriptions CASCADE;

-- -------------------------------------------------------------
-- 3. Functions
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS set_changed_at() CASCADE;

-- -------------------------------------------------------------
-- 4. Tables (reverse dependency order)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS tenant_usage_log     CASCADE;
DROP TABLE IF EXISTS client_subscriptions CASCADE;
DROP TABLE IF EXISTS instances            CASCADE;
DROP TABLE IF EXISTS clients              CASCADE;
DROP TABLE IF EXISTS tiers                CASCADE;
DROP TABLE IF EXISTS settings             CASCADE;

COMMIT;
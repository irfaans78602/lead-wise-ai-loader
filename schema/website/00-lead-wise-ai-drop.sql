-- =============================================================
-- 00-lead-wise-ai-drop.sql
-- Drops everything created by 10-lead-wise-ai-schema.sql.
-- Run before 10-lead-wise-ai-schema.sql for a clean rebuild.
-- Postgres 14+.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- 1. Views
-- -------------------------------------------------------------
DROP VIEW IF EXISTS active_ads_with_merged_emails CASCADE;
DROP VIEW IF EXISTS active_ads_with_active_clients CASCADE;
DROP VIEW IF EXISTS active_client_users            CASCADE;
DROP VIEW IF EXISTS active_agency_users            CASCADE;
DROP VIEW IF EXISTS active_qualification_score     CASCADE;
DROP VIEW IF EXISTS active_qualification_levels    CASCADE;
DROP VIEW IF EXISTS active_faqs                    CASCADE;
DROP VIEW IF EXISTS active_ad_reopen_prompts       CASCADE;
DROP VIEW IF EXISTS active_ad_confirmations        CASCADE;
DROP VIEW IF EXISTS active_ads                     CASCADE;
DROP VIEW IF EXISTS active_client_messages         CASCADE;
DROP VIEW IF EXISTS active_clients                 CASCADE;
DROP VIEW IF EXISTS active_agencies                CASCADE;
DROP VIEW IF EXISTS active_pricing_addons          CASCADE;
DROP VIEW IF EXISTS active_pricing_website         CASCADE;
DROP VIEW IF EXISTS active_pricing_rates           CASCADE;
DROP VIEW IF EXISTS active_pricing_segment_tiers   CASCADE;
DROP VIEW IF EXISTS active_pricing_tiers           CASCADE;
DROP VIEW IF EXISTS active_pricing_discounts       CASCADE;
DROP VIEW IF EXISTS active_settings                CASCADE;
DROP VIEW IF EXISTS active_messages                CASCADE;
DROP VIEW IF EXISTS active_segments                CASCADE;
DROP VIEW IF EXISTS active_countries               CASCADE;
DROP VIEW IF EXISTS active_currencies              CASCADE;
DROP VIEW IF EXISTS active_languages               CASCADE;

-- -------------------------------------------------------------
-- 2. Tables
-- -------------------------------------------------------------
DROP TABLE IF EXISTS answers                 CASCADE;
DROP TABLE IF EXISTS qualifications          CASCADE;
DROP TABLE IF EXISTS customer_statuses       CASCADE;
DROP TABLE IF EXISTS conversations           CASCADE;
DROP TABLE IF EXISTS customers               CASCADE;
DROP TABLE IF EXISTS qualification_score     CASCADE;

DROP TABLE IF EXISTS faqs                    CASCADE;
DROP TABLE IF EXISTS ad_confirmations        CASCADE;
DROP TABLE IF EXISTS ad_reopen_prompts       CASCADE;
DROP TABLE IF EXISTS ads                     CASCADE;

DROP TABLE IF EXISTS pricing_discounts       CASCADE;
DROP TABLE IF EXISTS pricing_addons          CASCADE;
DROP TABLE IF EXISTS pricing_website         CASCADE;
DROP TABLE IF EXISTS pricing_rates           CASCADE;
DROP TABLE IF EXISTS pricing_segment_tiers   CASCADE;
DROP TABLE IF EXISTS pricing_tiers           CASCADE;

DROP TABLE IF EXISTS invoice_payments        CASCADE;
DROP TABLE IF EXISTS client_messages         CASCADE;
DROP TABLE IF EXISTS client_users            CASCADE;
DROP TABLE IF EXISTS agency_users            CASCADE;
-- Superseded early draft of the CORS allowlist (now clients.allowed_origins).
DROP TABLE IF EXISTS client_allowed_origins CASCADE;
DROP TABLE IF EXISTS clients                 CASCADE;
DROP TABLE IF EXISTS agencies                CASCADE;

DROP TABLE IF EXISTS qualification_levels    CASCADE;

DROP TABLE IF EXISTS settings                CASCADE;
DROP TABLE IF EXISTS messages                CASCADE;
DROP TABLE IF EXISTS message_rate_limits     CASCADE;

-- Append-only runtime logs
DROP TABLE IF EXISTS contacts                CASCADE;

DROP TABLE IF EXISTS segments                CASCADE;
DROP TABLE IF EXISTS countries               CASCADE;
DROP TABLE IF EXISTS currencies              CASCADE;
DROP TABLE IF EXISTS languages               CASCADE;

-- -------------------------------------------------------------
-- 3. Functions (after tables, so no trigger still uses them)
-- -------------------------------------------------------------
-- Catch every possible signature of effective_ad_id from past migrations
DROP FUNCTION IF EXISTS effective_ad_id(bigint)           CASCADE;
DROP FUNCTION IF EXISTS effective_ad_id(text)             CASCADE;
DROP FUNCTION IF EXISTS effective_ad_id(varchar)          CASCADE;
DROP FUNCTION IF EXISTS effective_ad_id(uuid)             CASCADE;

-- Other trigger functions
DROP FUNCTION IF EXISTS forbid_content_on_leaf_ad()       CASCADE;
DROP FUNCTION IF EXISTS sync_customer_current_status()    CASCADE;
DROP FUNCTION IF EXISTS set_updated_at()                  CASCADE;

-- -------------------------------------------------------------
-- 4. Commit point at end; section 5 only reports.
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- 5. Leftover report (warnings only, never aborts)
-- -------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname AS name, c.relkind::text AS kind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r','p','v','m','f')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = c.oid AND d.deptype = 'e')
    ORDER BY c.relname
  LOOP
    RAISE WARNING 'Left over (relation, kind %): public.%', r.kind, r.name;
  END LOOP;

  FOR r IN
    SELECT t.typname AS name
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typtype IN ('e','d')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = t.oid AND d.deptype = 'e')
    ORDER BY t.typname
  LOOP
    RAISE WARNING 'Left over (type): public.%', r.name;
  END LOOP;

  FOR r IN
    SELECT p.proname AS name
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.objid = p.oid AND d.deptype = 'e')
    ORDER BY p.proname
  LOOP
    RAISE WARNING 'Left over (function): public.%', r.name;
  END LOOP;
END $$;

COMMIT;
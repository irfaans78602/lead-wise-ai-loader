-- =============================================================
-- 00-drop-website.sql
-- Drops everything created by 10-schema-website.sql.
-- =============================================================

BEGIN;

-- -------------------------------------------------------------
-- Views first
-- -------------------------------------------------------------
DROP VIEW IF EXISTS v_live_chat_dropoff             CASCADE;
DROP VIEW IF EXISTS v_live_chat_funnel              CASCADE;
DROP VIEW IF EXISTS v_live_chat_by_question         CASCADE;
DROP VIEW IF EXISTS active_ads_with_merged_emails  CASCADE;
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
DROP VIEW IF EXISTS active_client_services         CASCADE;
DROP VIEW IF EXISTS active_clients                 CASCADE;
DROP VIEW IF EXISTS active_agencies                CASCADE;
DROP VIEW IF EXISTS active_pricing_pilot           CASCADE;
DROP VIEW IF EXISTS active_pricing_discounts       CASCADE;
DROP VIEW IF EXISTS active_pricing_addons          CASCADE;
DROP VIEW IF EXISTS active_pricing_website         CASCADE;
DROP VIEW IF EXISTS active_pricing_rates           CASCADE;
DROP VIEW IF EXISTS active_pricing_segment_tiers   CASCADE;
DROP VIEW IF EXISTS active_pricing_tiers           CASCADE;
DROP VIEW IF EXISTS active_settings                CASCADE;
DROP VIEW IF EXISTS active_messages                CASCADE;
DROP VIEW IF EXISTS active_segments                CASCADE;
DROP VIEW IF EXISTS active_countries               CASCADE;
DROP VIEW IF EXISTS active_currencies              CASCADE;
DROP VIEW IF EXISTS active_languages               CASCADE;

-- -------------------------------------------------------------
-- Triggers
-- -------------------------------------------------------------
DROP TRIGGER IF EXISTS faqs_root_only                ON faqs                CASCADE;
DROP TRIGGER IF EXISTS ad_confirmations_root_only    ON ad_confirmations    CASCADE;
DROP TRIGGER IF EXISTS ad_reopen_prompts_root_only   ON ad_reopen_prompts   CASCADE;
DROP TRIGGER IF EXISTS qualification_score_root_only ON qualification_score CASCADE;

DROP TRIGGER IF EXISTS customers_updated_at          ON customers          CASCADE;
DROP TRIGGER IF EXISTS conversations_updated_at      ON conversations      CASCADE;
DROP TRIGGER IF EXISTS client_users_updated_at       ON client_users       CASCADE;
DROP TRIGGER IF EXISTS agency_users_updated_at       ON agency_users       CASCADE;
DROP TRIGGER IF EXISTS settings_updated_at           ON settings           CASCADE;
DROP TRIGGER IF EXISTS invoice_payments_updated_at   ON invoice_payments   CASCADE;

DROP TRIGGER IF EXISTS customer_statuses_sync_current  ON customer_statuses  CASCADE;
DROP TRIGGER IF EXISTS client_services_no_wildcard_mix ON client_services    CASCADE;

-- -------------------------------------------------------------
-- Functions
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS forbid_content_on_leaf_ad()       CASCADE;
DROP FUNCTION IF EXISTS sync_customer_current_status()     CASCADE;
DROP FUNCTION IF EXISTS effective_ad_id(TEXT)              CASCADE;
DROP FUNCTION IF EXISTS set_updated_at()                   CASCADE;
DROP FUNCTION IF EXISTS forbid_wildcard_locale_mix()       CASCADE;

-- -------------------------------------------------------------
-- Tables
-- -------------------------------------------------------------
DROP TABLE IF EXISTS live_chat_logs           CASCADE;
DROP TABLE IF EXISTS customer_statuses        CASCADE;
DROP TABLE IF EXISTS qualifications           CASCADE;
DROP TABLE IF EXISTS answers                  CASCADE;
DROP TABLE IF EXISTS conversations            CASCADE;
DROP TABLE IF EXISTS customers                CASCADE;
DROP TABLE IF EXISTS demo_sessions            CASCADE;
DROP TABLE IF EXISTS contacts                 CASCADE;
DROP TABLE IF EXISTS invoice_payments         CASCADE;
DROP TABLE IF EXISTS message_rate_limits      CASCADE;

DROP TABLE IF EXISTS ad_confirmations         CASCADE;
DROP TABLE IF EXISTS ad_reopen_prompts        CASCADE;
DROP TABLE IF EXISTS faqs                     CASCADE;
DROP TABLE IF EXISTS qualification_score      CASCADE;
DROP TABLE IF EXISTS qualification_levels     CASCADE;

DROP TABLE IF EXISTS ads                      CASCADE;

DROP TABLE IF EXISTS client_messages          CASCADE;
DROP TABLE IF EXISTS client_services          CASCADE;
DROP TABLE IF EXISTS client_users             CASCADE;
DROP TABLE IF EXISTS agency_users             CASCADE;
DROP TABLE IF EXISTS pricing_discounts        CASCADE;
DROP TABLE IF EXISTS pricing_addons           CASCADE;
DROP TABLE IF EXISTS pricing_pilot            CASCADE;
DROP TABLE IF EXISTS pricing_website          CASCADE;
DROP TABLE IF EXISTS pricing_rates            CASCADE;
DROP TABLE IF EXISTS pricing_segment_tiers    CASCADE;

DROP TABLE IF EXISTS clients                  CASCADE;

DROP TABLE IF EXISTS agencies                 CASCADE;
DROP TABLE IF EXISTS segments                 CASCADE;
DROP TABLE IF EXISTS countries                CASCADE;
DROP TABLE IF EXISTS currencies               CASCADE;
DROP TABLE IF EXISTS languages                CASCADE;

DROP TABLE IF EXISTS messages                 CASCADE;
DROP TABLE IF EXISTS settings                 CASCADE;
DROP TABLE IF EXISTS pricing_tiers            CASCADE;

COMMIT;
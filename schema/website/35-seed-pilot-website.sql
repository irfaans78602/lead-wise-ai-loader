-- =============================================================
-- 35-seed-pilot-website.sql
-- Pilot discount bootstrap (all currencies) for LeadWise AI.
-- Run after 20-seed-base-website.sql.
-- Independent of the pricing-rate seeds (30/40/50).
-- Safe to re-run: all inserts are idempotent.
--
-- The pilot programme gives new clients:
--   * 50% off the one-time website setup fee
--     (R4,950 → R2,475, £223 → £111.50, $298 → $149.00)
--   * 50% off the monthly base fee for 6 months
--   * Per-lead fees at full price
--
-- These percentages live in the DB so the pilot card on
-- /pricing can be built entirely from server data, with no
-- hardcoded figures in _shared.json.
--
-- The amounts the percentages apply to come from
-- pricing_website (setup, extra page) and pricing_rates
-- (base fee), so they update when those tables change.
-- =============================================================

BEGIN;

-- =============================================================
-- Pilot discount schedule — one row per country.
-- Currently identical across ZA, GB, US, but stored per-country
-- so a future country can launch with different terms without
-- a schema change.
-- =============================================================
INSERT INTO pricing_pilot
    (country_id, setup_discount_pct, base_discount_pct, duration_months)
SELECT co.country_id, v.setup_pct, v.base_pct, v.months
FROM (VALUES
    ('ZA', 50.00, 50.00, 6),
    ('GB', 50.00, 50.00, 6),
    ('US', 50.00, 50.00, 6)
) AS v(country_code, setup_pct, base_pct, months)
JOIN countries co ON co.code = v.country_code
ON CONFLICT (country_id, start_date) DO NOTHING;

COMMIT;
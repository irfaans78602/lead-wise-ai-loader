-- =============================================================
-- 50-seed-pricing-usd-website.sql
-- Pricing bootstrap (USD, United States) for LeadWise AI.
-- Run after 20-seed-base-website.sql.
-- Independent of the other two pricing seeds.
-- Safe to re-run: all inserts are idempotent.
--
-- FX reference rate used for this snapshot:
--   USD/ZAR = 16.6215  (31 October 2026)
-- All USD values are the ZAR value divided by 16.6215,
-- rounded to the nearest whole unit (.50 rounds up).
-- Update these values when the reference rate moves more
-- than ~2% from the rate noted above.
--
-- Source: https://lead-wise-ai.com/pricing (USD tab).
--
-- Contents:
--   1. pricing_rates    (4 tiers — US, USD via country default)
--   2. pricing_website  (one-time setup fee, US)
--   3. pricing_addons   (SEO + Ads Management, US)
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Pricing Rates — 4 tiers — US.
-- ZAR ÷ 16.6215, rounded to whole unit.
--   standard:     R500 → $30  | R1,000 → $60 | R25 → $1.50 | R34 → $2.05
--   professional: R1,000 → $60 | R1,500 → $90 | R35 → $2.11 | R46 → $2.77
--   high_value:   R1,500 → $90 | R2,500 → $150 | R47 → $2.83 | R60 → $3.61
--   premium:      R2,500 → $150 | R4,000 → $241 | R61 → $3.67 | R75 → $4.51
-- =============================================================
INSERT INTO pricing_rates
    (tier_id, country_id,
     base_fee_min, base_fee_max,
     per_lead_min, per_lead_max)
SELECT t.tier_id, co.country_id,
       v.base_fee_min, v.base_fee_max,
       v.per_lead_min, v.per_lead_max
FROM (VALUES
    ('standard',       30.00,   60.00, 1.50, 2.05),
    ('professional',   60.00,   90.00, 2.11, 2.77),
    ('high_value',     90.00,  150.00, 2.83, 3.61),
    ('premium',       150.00,  241.00, 3.67, 4.51)
) AS v(tier_code, base_fee_min, base_fee_max, per_lead_min, per_lead_max)
JOIN pricing_tiers t ON t.tier_code = v.tier_code
CROSS JOIN countries co
WHERE co.code = 'US'
ON CONFLICT (tier_id, country_id, start_date) DO NOTHING;

-- =============================================================
-- 2. Pricing Website — US.
--    Setup: R4,950 ÷ 16.6215 = $297.88 → $298
--    Extra: R950   ÷ 16.6215 = $57.16  → $57
-- =============================================================
INSERT INTO pricing_website (country_id, setup_fee, extra_page_fee)
SELECT co.country_id, 298.00, 57.00
FROM countries co
WHERE co.code = 'US'
ON CONFLICT (country_id, start_date) DO NOTHING;

-- =============================================================
-- 3. Pricing Addons — SEO and Ads Management, US.
--    SEO:       setup R500 ÷ 16.6215 = $30.08 → $30
--               monthly_min R500 ÷ 16.6215 = $30
--               monthly_max R3,000 ÷ 16.6215 = $180.49 → $180
--    Ads mgmt:  setup R1,500 ÷ 16.6215 = $90.25 → $90
--               pct_of_ad_spend 6%–15% (currency-agnostic)
--               minimum_monthly_fee R1,500 ÷ 16.6215 = $90
-- =============================================================
INSERT INTO pricing_addons
    (addon_code, country_id,
     setup_fee, monthly_fee_min, monthly_fee_max,
     pct_of_ad_spend_min, pct_of_ad_spend_max,
     minimum_monthly_fee)
SELECT v.addon_code, co.country_id,
       v.setup_fee, v.monthly_fee_min, v.monthly_fee_max,
       v.pct_min, v.pct_max,
       v.min_monthly
FROM (VALUES
    ('seo',       30.00,  30.00, 180.00, NULL::numeric, NULL::numeric, NULL::numeric),
    ('ads_mgmt',  90.00, NULL,    NULL,   6.00,          15.00,          90.00)
) AS v(addon_code, setup_fee, monthly_fee_min, monthly_fee_max,
       pct_min, pct_max, min_monthly)
CROSS JOIN countries co
WHERE co.code = 'US'
ON CONFLICT (addon_code, country_id, start_date) DO NOTHING;

COMMIT;
-- =============================================================
-- 30-seed-pricing-zar-website.sql
-- Pricing bootstrap (ZAR, South Africa) for LeadWise AI.
-- Run after 20-seed-base-website.sql.
-- Independent of the other two pricing seeds.
-- Safe to re-run: all inserts are idempotent.
--
-- Source: https://lead-wise-ai.com/pricing (ZAR tab).
--
-- Contents:
--   1. pricing_rates    (4 tiers — ZA, ZAR via country default)
--   2. pricing_website  (one-time setup fee, ZA)
--   3. pricing_addons   (SEO + Ads Management, ZA)
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Pricing Rates — 4 tiers — ZA.
-- =============================================================
INSERT INTO pricing_rates
    (tier_id, country_id,
     base_fee_min, base_fee_max,
     per_lead_min, per_lead_max)
SELECT t.tier_id, co.country_id,
       v.base_fee_min, v.base_fee_max,
       v.per_lead_min, v.per_lead_max
FROM (VALUES
    ('standard',      500.00, 1000.00, 25.00, 34.00),
    ('professional', 1000.00, 1500.00, 35.00, 46.00),
    ('high_value',   1500.00, 2500.00, 47.00, 60.00),
    ('premium',      2500.00, 4000.00, 61.00, 75.00)
) AS v(tier_code, base_fee_min, base_fee_max, per_lead_min, per_lead_max)
JOIN pricing_tiers t ON t.tier_code = v.tier_code
CROSS JOIN countries co
WHERE co.code = 'ZA'
ON CONFLICT (tier_id, country_id, start_date) DO NOTHING;

-- =============================================================
-- 2. Pricing Website — ZA.
--    Pilot: 50% off (R2,475 setup, R475 per extra page).
-- =============================================================
INSERT INTO pricing_website (country_id, setup_fee, extra_page_fee)
SELECT co.country_id, 4950.00, 950.00
FROM countries co
WHERE co.code = 'ZA'
ON CONFLICT (country_id, start_date) DO NOTHING;

-- =============================================================
-- 3. Pricing Addons — SEO and Ads Management, ZA.
--    SEO:       setup fee + monthly fee (from R500/month).
--    Ads mgmt:  setup fee + 6–15% of ad spend, or the minimum
--               monthly fee, whichever is higher.
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
    ('seo',       500.00,  500.00, 3000.00, NULL::numeric, NULL::numeric, NULL::numeric),
    ('ads_mgmt', 1500.00, NULL,    NULL,    6.00,          15.00,          1500.00)
) AS v(addon_code, setup_fee, monthly_fee_min, monthly_fee_max,
       pct_min, pct_max, min_monthly)
CROSS JOIN countries co
WHERE co.code = 'ZA'
ON CONFLICT (addon_code, country_id, start_date) DO NOTHING;

COMMIT;
-- =============================================================
-- 50-lead-wise-ai-seed-pricing-usd.sql
-- Pricing bootstrap (USD, United States) for LeadWise AI.
-- Run after 20-lead-wise-ai-seed-base.sql.
-- Independent of the other two pricing seeds.
-- Safe to re-run: all inserts are idempotent.
--
-- Source: https://lead-wise-ai.com/pricing (USD tab).
--
-- Contents:
--   1. pricing_rates    (4 tiers Ã— US, USD via country default)
--   2. pricing_website  (one-time setup fee, US)
--   3. pricing_addons   (SEO + Ads Management, US)
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Pricing Rates â€” 4 tiers Ã— US.
-- =============================================================
INSERT INTO pricing_rates
    (tier_id, country_id,
     base_fee_min, base_fee_max,
     per_lead_min, per_lead_max)
SELECT t.tier_id, co.country_id,
       v.base_fee_min, v.base_fee_max,
       v.per_lead_min, v.per_lead_max
FROM (VALUES
    ('standard',       30.00,   61.00, 1.50, 2.05),
    ('professional',   61.00,   91.00, 2.10, 2.80),
    ('high_value',     91.00,  152.00, 2.85, 3.65),
    ('premium',       152.00,  244.00, 3.70, 4.55)
) AS v(tier_code, base_fee_min, base_fee_max, per_lead_min, per_lead_max)
JOIN pricing_tiers t ON t.tier_code = v.tier_code
CROSS JOIN countries co
WHERE co.code = 'US'
ON CONFLICT (tier_id, country_id, start_date) DO NOTHING;

-- =============================================================
-- 2. Pricing Website â€” US.
--    Pilot: 50% off ($151 setup, $29 per extra page).
-- =============================================================
INSERT INTO pricing_website (country_id, setup_fee, extra_page_fee)
SELECT co.country_id, 302.00, 58.00
FROM countries co
WHERE co.code = 'US'
ON CONFLICT (country_id, start_date) DO NOTHING;

-- =============================================================
-- 3. Pricing Addons â€” SEO and Ads Management, US.
--    SEO:       setup fee $30 + monthly fee from $30/month.
--    Ads mgmt:  setup fee $91 + 6â€“15% of ad spend, or the
--               minimum monthly fee of $91, whichever is higher.
--
--    Values match the USD tab on https://lead-wise-ai.com/pricing.
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
    ('seo',       30.00,  30.00, 400.00, NULL::numeric, NULL::numeric, NULL::numeric),
    ('ads_mgmt',  91.00, NULL,    NULL,   6.00,          15.00,           91.00)
) AS v(addon_code, setup_fee, monthly_fee_min, monthly_fee_max,
       pct_min, pct_max, min_monthly)
CROSS JOIN countries co
WHERE co.code = 'US'
ON CONFLICT (addon_code, country_id, start_date) DO NOTHING;

COMMIT;
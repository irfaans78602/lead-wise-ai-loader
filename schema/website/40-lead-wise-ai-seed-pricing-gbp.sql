-- =============================================================
-- 40-lead-wise-ai-seed-pricing-gbp.sql
-- Pricing bootstrap (GBP, United Kingdom) for LeadWise AI.
-- Run after 20-lead-wise-ai-seed-base.sql.
-- Independent of the other two pricing seeds.
-- Safe to re-run: all inserts are idempotent.
--
-- Source: https://lead-wise-ai.com/pricing (GBP tab).
--
-- Contents:
--   1. pricing_rates    (4 tiers Ã— GB, GBP via country default)
--   2. pricing_website  (one-time setup fee, GB)
--   3. pricing_addons   (SEO + Ads Management, GB)
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Pricing Rates â€” 4 tiers Ã— GB.
-- =============================================================
INSERT INTO pricing_rates
    (tier_id, country_id,
     base_fee_min, base_fee_max,
     per_lead_min, per_lead_max)
SELECT t.tier_id, co.country_id,
       v.base_fee_min, v.base_fee_max,
       v.per_lead_min, v.per_lead_max
FROM (VALUES
    ('standard',       23.00,   46.00, 1.15, 1.55),
    ('professional',   46.00,   69.00, 1.60, 2.10),
    ('high_value',     69.00,  115.00, 2.15, 2.75),
    ('premium',       115.00,  184.00, 2.80, 3.45)
) AS v(tier_code, base_fee_min, base_fee_max, per_lead_min, per_lead_max)
JOIN pricing_tiers t ON t.tier_code = v.tier_code
CROSS JOIN countries co
WHERE co.code = 'GB'
ON CONFLICT (tier_id, country_id, start_date) DO NOTHING;

-- =============================================================
-- 2. Pricing Website â€” GB.
--    Pilot: 50% off (Â£114 setup, Â£22 per extra page).
-- =============================================================
INSERT INTO pricing_website (country_id, setup_fee, extra_page_fee)
SELECT co.country_id, 228.00, 44.00
FROM countries co
WHERE co.code = 'GB'
ON CONFLICT (country_id, start_date) DO NOTHING;

-- =============================================================
-- 3. Pricing Addons â€” SEO and Ads Management, GB.
--    SEO:       setup fee Â£23 + monthly fee from Â£23/month.
--    Ads mgmt:  setup fee Â£69 + 6â€“15% of ad spend, or the
--               minimum monthly fee of Â£69, whichever is higher.
--
--    Values match the GBP tab on https://lead-wise-ai.com/pricing.
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
    ('seo',       23.00,  23.00, 300.00, NULL::numeric, NULL::numeric, NULL::numeric),
    ('ads_mgmt',  69.00, NULL,    NULL,   6.00,          15.00,           69.00)
) AS v(addon_code, setup_fee, monthly_fee_min, monthly_fee_max,
       pct_min, pct_max, min_monthly)
CROSS JOIN countries co
WHERE co.code = 'GB'
ON CONFLICT (addon_code, country_id, start_date) DO NOTHING;

COMMIT;
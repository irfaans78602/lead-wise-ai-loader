-- =============================================================
-- 10-schema-website.sql
-- Multi-tenant lead-qualification backend. Postgres 14+.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- =============================================================
-- 1. Languages
-- =============================================================
CREATE TABLE languages (
    language_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          VARCHAR(15) NOT NULL UNIQUE
                  CHECK (code ~ '^[a-z]{2}(-[A-Za-z0-9]+)*$'),
    name          TEXT NOT NULL,
    native_name   TEXT NOT NULL,
    start_date    DATE NOT NULL DEFAULT '1900-01-01',
    end_date      DATE NOT NULL DEFAULT '9999-12-31',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX languages_active_idx ON languages (start_date, end_date);

-- =============================================================
-- 2. Currencies
-- =============================================================
CREATE TABLE currencies (
    currency_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          CHAR(3) NOT NULL UNIQUE
                  CHECK (code ~ '^[A-Z]{3}$'),
    name          TEXT NOT NULL,
    symbol        TEXT NOT NULL,
    minor_unit    SMALLINT NOT NULL DEFAULT 2,
    start_date    DATE NOT NULL DEFAULT '1900-01-01',
    end_date      DATE NOT NULL DEFAULT '9999-12-31',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX currencies_active_idx ON currencies (start_date, end_date);

-- =============================================================
-- 3. Countries
-- =============================================================
CREATE TABLE countries (
    country_id           SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                 CHAR(2) NOT NULL UNIQUE
                         CHECK (code ~ '^[A-Z]{2}$'),
    name                 TEXT NOT NULL,
    default_language_id  SMALLINT NOT NULL REFERENCES languages(language_id) ON DELETE RESTRICT,
    default_currency_id  SMALLINT NOT NULL REFERENCES currencies(currency_id) ON DELETE RESTRICT,
    start_date           DATE NOT NULL DEFAULT '1900-01-01',
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX countries_active_idx ON countries (start_date, end_date);

-- =============================================================
-- 4. Segments
-- =============================================================
CREATE TABLE segments (
    segment_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    start_date    DATE NOT NULL DEFAULT '1900-01-01',
    end_date      DATE NOT NULL DEFAULT '9999-12-31',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX segments_code_idx   ON segments (code);
CREATE INDEX segments_active_idx ON segments (start_date, end_date);

-- =============================================================
-- 5. Messages
-- =============================================================
CREATE TABLE messages (
    message_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_code  TEXT NOT NULL UNIQUE,
    message_text  JSONB NOT NULL,
    description   TEXT,
    start_date    DATE NOT NULL DEFAULT '1900-01-01',
    end_date      DATE NOT NULL DEFAULT '9999-12-31',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date),
    CHECK (jsonb_typeof(message_text) = 'object')
);
CREATE INDEX messages_code_idx   ON messages (message_code);
CREATE INDEX messages_active_idx ON messages (start_date, end_date);

-- =============================================================
-- 6. Pricing Tiers
-- =============================================================
CREATE TABLE pricing_tiers (
    tier_id       SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tier_code     TEXT NOT NULL UNIQUE,
    tier_name     TEXT NOT NULL,
    tier_order    SMALLINT NOT NULL UNIQUE,
    description   TEXT,
    start_date    DATE NOT NULL DEFAULT '1900-01-01',
    end_date      DATE NOT NULL DEFAULT '9999-12-31',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date),
    CHECK (tier_order >= 1)
);
CREATE INDEX pricing_tiers_active_idx ON pricing_tiers (start_date, end_date);

-- =============================================================
-- 7. Pricing Segment Tiers
-- =============================================================
CREATE TABLE pricing_segment_tiers (
    segment_tier_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    segment_id       SMALLINT NOT NULL REFERENCES segments(segment_id) ON DELETE RESTRICT,
    tier_id          SMALLINT NOT NULL REFERENCES pricing_tiers(tier_id) ON DELETE RESTRICT,
    start_date       DATE NOT NULL DEFAULT '1900-01-01',
    end_date         DATE NOT NULL DEFAULT '9999-12-31',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (segment_id, start_date),
    CHECK (start_date <= end_date)
);
CREATE INDEX pricing_segment_tiers_segment_idx ON pricing_segment_tiers (segment_id);
CREATE INDEX pricing_segment_tiers_tier_idx    ON pricing_segment_tiers (tier_id);
CREATE INDEX pricing_segment_tiers_active_idx  ON pricing_segment_tiers (start_date, end_date);

-- =============================================================
-- 8. Pricing Rates
-- =============================================================
CREATE TABLE pricing_rates (
    rate_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tier_id          SMALLINT NOT NULL REFERENCES pricing_tiers(tier_id) ON DELETE RESTRICT,
    country_id       SMALLINT NOT NULL REFERENCES countries(country_id) ON DELETE RESTRICT,
    base_fee_min     NUMERIC(10,2) NOT NULL,
    base_fee_max     NUMERIC(10,2) NOT NULL,
    per_lead_min     NUMERIC(10,2) NOT NULL,
    per_lead_max     NUMERIC(10,2) NOT NULL,
    start_date       DATE NOT NULL DEFAULT '1900-01-01',
    end_date         DATE NOT NULL DEFAULT '9999-12-31',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tier_id, country_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (base_fee_min >= 0),
    CHECK (base_fee_max >= base_fee_min),
    CHECK (per_lead_min >= 0),
    CHECK (per_lead_max >= per_lead_min)
);
CREATE INDEX pricing_rates_tier_idx     ON pricing_rates (tier_id);
CREATE INDEX pricing_rates_country_idx  ON pricing_rates (country_id);
CREATE INDEX pricing_rates_active_idx   ON pricing_rates (start_date, end_date);

-- =============================================================
-- 9. Pricing Website
-- =============================================================
CREATE TABLE pricing_website (
    website_pricing_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_id         SMALLINT NOT NULL REFERENCES countries(country_id) ON DELETE RESTRICT,
    setup_fee          NUMERIC(10,2) NOT NULL,
    extra_page_fee     NUMERIC(10,2) NOT NULL,
    start_date         DATE NOT NULL DEFAULT '1900-01-01',
    end_date           DATE NOT NULL DEFAULT '9999-12-31',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (country_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (setup_fee >= 0),
    CHECK (extra_page_fee >= 0)
);
CREATE INDEX pricing_website_country_idx ON pricing_website (country_id);
CREATE INDEX pricing_website_active_idx  ON pricing_website (start_date, end_date);

-- =============================================================
-- 10. Pricing Addons
-- =============================================================
CREATE TABLE pricing_addons (
    addon_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    addon_code           TEXT NOT NULL
                         CHECK (addon_code IN ('seo','ads_mgmt')),
    country_id           SMALLINT NOT NULL REFERENCES countries(country_id) ON DELETE RESTRICT,
    setup_fee            NUMERIC(10,2),
    monthly_fee_min      NUMERIC(10,2),
    monthly_fee_max      NUMERIC(10,2),
    pct_of_ad_spend_min  NUMERIC(5,2),
    pct_of_ad_spend_max  NUMERIC(5,2),
    minimum_monthly_fee  NUMERIC(10,2),
    start_date           DATE NOT NULL DEFAULT '1900-01-01',
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (addon_code, country_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (setup_fee IS NULL OR setup_fee >= 0),
    CHECK (monthly_fee_min IS NULL OR monthly_fee_min >= 0),
    CHECK (monthly_fee_max IS NULL OR monthly_fee_max >= monthly_fee_min),
    CHECK (pct_of_ad_spend_min IS NULL OR pct_of_ad_spend_min >= 0),
    CHECK (pct_of_ad_spend_max IS NULL OR pct_of_ad_spend_max >= pct_of_ad_spend_min),
    CHECK (pct_of_ad_spend_min IS NULL OR pct_of_ad_spend_min <= 100),
    CHECK (pct_of_ad_spend_max IS NULL OR pct_of_ad_spend_max <= 100),
    CHECK (minimum_monthly_fee IS NULL OR minimum_monthly_fee >= 0),
    CHECK (
        (addon_code = 'seo'
         AND pct_of_ad_spend_min IS NULL
         AND pct_of_ad_spend_max IS NULL
         AND minimum_monthly_fee IS NULL)
        OR
        (addon_code = 'ads_mgmt'
         AND pct_of_ad_spend_min IS NOT NULL
         AND pct_of_ad_spend_max IS NOT NULL
         AND minimum_monthly_fee IS NOT NULL)
    )
);
CREATE INDEX pricing_addons_code_idx    ON pricing_addons (addon_code);
CREATE INDEX pricing_addons_country_idx ON pricing_addons (country_id);
CREATE INDEX pricing_addons_active_idx  ON pricing_addons (start_date, end_date);

-- =============================================================
-- 10.1 Pricing Pilot
-- =============================================================
CREATE TABLE pricing_pilot (
    pilot_pricing_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_id           SMALLINT NOT NULL REFERENCES countries(country_id) ON DELETE RESTRICT,
    setup_discount_pct   NUMERIC(5,2) NOT NULL,
    base_discount_pct    NUMERIC(5,2) NOT NULL,
    duration_months      SMALLINT NOT NULL,
    start_date           DATE NOT NULL DEFAULT '1900-01-01',
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (country_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (setup_discount_pct >= 0 AND setup_discount_pct <= 100),
    CHECK (base_discount_pct  >= 0 AND base_discount_pct  <= 100),
    CHECK (duration_months    >= 1)
);
CREATE INDEX pricing_pilot_country_idx ON pricing_pilot (country_id);
CREATE INDEX pricing_pilot_active_idx  ON pricing_pilot (start_date, end_date);

-- =============================================================
-- 11. Agencies
-- =============================================================
CREATE TABLE agencies (
    agency_id         UUID PRIMARY KEY,
    name              TEXT NOT NULL,
    email_to          TEXT NOT NULL,
    email_cc          TEXT,
    email_bcc         TEXT,
    parent_agency_id  UUID REFERENCES agencies(agency_id) ON DELETE RESTRICT,
    start_date        DATE NOT NULL DEFAULT '1900-01-01',
    end_date          DATE NOT NULL DEFAULT '9999-12-31',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (parent_agency_id IS NULL OR parent_agency_id <> agency_id),
    CHECK (start_date <= end_date)
);
CREATE INDEX agencies_parent_idx ON agencies (parent_agency_id);
CREATE INDEX agencies_active_idx ON agencies (start_date, end_date);

-- =============================================================
-- 12. Clients
-- =============================================================
CREATE TABLE clients (
    client_id            UUID PRIMARY KEY,
    name                 TEXT NOT NULL,
    email_to             TEXT NOT NULL,
    email_cc             TEXT,
    email_bcc            TEXT,
    
    -- Controls the "From" address in Resend
    email_from_name      TEXT, 
    email_from_prefix    TEXT DEFAULT 'hello', 
    
    -- Data-driven response time for prospect emails (Localized)
    response_time_expectation JSONB NOT NULL DEFAULT '{
        "en": "few hours",
        "es": "pocas horas",
        "ar": "ساعات قليلة",
        "fr": "quelques heures",
        "zh": "几个小时"
    }'::jsonb,
    
    sms_numbers          JSONB NOT NULL DEFAULT '{}'::jsonb,
    agency_id            UUID REFERENCES agencies(agency_id) ON DELETE SET NULL,
    country_id           SMALLINT REFERENCES countries(country_id) ON DELETE RESTRICT,
    segment_id           SMALLINT REFERENCES segments(segment_id) ON DELETE RESTRICT,
    currency_id          SMALLINT REFERENCES currencies(currency_id) ON DELETE RESTRICT,
    language_id          SMALLINT REFERENCES languages(language_id) ON DELETE RESTRICT,
    is_platform_owner    BOOLEAN NOT NULL DEFAULT FALSE,
    is_pilot             BOOLEAN NOT NULL DEFAULT FALSE,
    pilot_ends_on        DATE,
    closed_behavior      TEXT NOT NULL DEFAULT 'reply'
                         CHECK (closed_behavior IN ('reply','silent')),
    reopen_policy        TEXT NOT NULL DEFAULT 'reopen'
                         CHECK (reopen_policy IN ('reopen','prompt','forward')),
    allowed_origins      TEXT NOT NULL DEFAULT ''
                         CHECK (allowed_origins = ''
                                OR allowed_origins ~ '^https?://[a-z0-9.-]+(:[0-9]{1,5})?(,https?://[a-z0-9.-]+(:[0-9]{1,5})?)*$'),

    -- Data-driven display columns for the Leads table (faqs.question_id references)
	lead_transactions_title              JSONB,
    display_first_name_question_id       SMALLINT,
    display_last_name_question_id        SMALLINT,
    display_phone_number_question_id     SMALLINT,
	display_email_address_question_id    SMALLINT,

    start_date           DATE NOT NULL DEFAULT '1900-01-01',
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CHECK (start_date <= end_date),
    CHECK (NOT is_pilot OR pilot_ends_on IS NOT NULL),
    CHECK (
        is_platform_owner = TRUE
        OR
        (country_id IS NOT NULL AND segment_id IS NOT NULL AND currency_id IS NOT NULL)
    )
);
CREATE INDEX clients_agency_idx  ON clients (agency_id);
CREATE INDEX clients_country_idx ON clients (country_id);
CREATE INDEX clients_segment_idx ON clients (segment_id);
CREATE INDEX clients_active_idx  ON clients (start_date, end_date);
CREATE INDEX clients_sms_numbers_idx ON clients USING gin (sms_numbers);
CREATE UNIQUE INDEX clients_one_platform_owner ON clients ((is_platform_owner)) WHERE is_platform_owner = TRUE;

-- =============================================================
-- 12.1 Demo Sessions
-- =============================================================
CREATE TABLE demo_sessions (
    demo_session_id   UUID PRIMARY KEY,
    client_id         UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_active_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours')
);
CREATE INDEX demo_sessions_client_idx  ON demo_sessions (client_id);
CREATE INDEX demo_sessions_expires_idx ON demo_sessions (expires_at);

-- =============================================================
-- 12.2 Client Services
-- One row per billed line item per client. fee_cents is the unit
-- price; fee_basis determines how quantity is interpreted:
--
--   one_time   - charged once (website setup, onboarding)
--   per_page   - charged once, per page (extra pages)
--   per_lead   - charged per qualified lead, per billing cycle
--   monthly    - charged once per billing cycle (subscriptions)
--
-- locale_code is '*' for services that apply to all locales
-- (website setup), or a specific locale for services that vary
-- by market (per-lead rate, SEO, Ads, Ask AI Assist). A client
-- cannot have both a wildcard and a specific-locale current
-- contract for the same (service_code) -- enforced by trigger.
--
-- Active rows are those where CURRENT_DATE is between start_date
-- and end_date. The specific contracted fee lives here; the
-- published floor and ceiling live in pricing_* tables.
-- =============================================================
CREATE TABLE client_services (
    client_service_id  UUID PRIMARY KEY,
    client_id          UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    service_code       TEXT NOT NULL
                       CHECK (service_code IN (
                           'website_setup',
                           'website_extra_pages',
                           'lead_qualification',
                           'seo',
                           'ads_mgmt',
                           'ask_ai_public',
                           'ask_ai_internal'
                       )),
    locale_code        VARCHAR(5) NOT NULL DEFAULT '*'
                       CHECK (
                           locale_code = '*'
                           OR locale_code IN ('en', 'ar', 'es', 'fr', 'zh')
                       ),
    fee_cents          INT NOT NULL
                       CHECK (fee_cents >= 0),
    fee_basis          TEXT NOT NULL
                       CHECK (fee_basis IN (
                           'one_time',
                           'per_page',
                           'per_lead',
                           'monthly'
                       )),
    quantity           INT NOT NULL DEFAULT 1
                       CHECK (quantity >= 1),
    currency_code      CHAR(3) NOT NULL
                       CHECK (currency_code ~ '^[A-Z]{3}$'),
    start_date         DATE NOT NULL DEFAULT '1900-01-01',
    end_date           DATE NOT NULL DEFAULT '9999-12-31',
    notes              TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date),

    -- fee_basis must match service_code's inherent shape.
    CHECK (
        (service_code = 'website_setup'        AND fee_basis = 'one_time')
        OR
        (service_code = 'website_extra_pages'  AND fee_basis = 'per_page')
        OR
        (service_code = 'lead_qualification'   AND fee_basis = 'per_lead')
        OR
        (service_code IN ('seo', 'ads_mgmt', 'ask_ai_public', 'ask_ai_internal')
                                               AND fee_basis = 'monthly')
    ),

    -- website_setup is not locale-scoped; it must always use '*'.
    -- Everything else may be '*' or a specific locale, and the
    -- trigger below enforces that they don't mix.
    CHECK (service_code <> 'website_setup' OR locale_code = '*')
);

-- Primary lookup path: "what is this client paying for, right now?"
CREATE INDEX client_services_client_idx
    ON client_services (client_id, start_date, end_date);

-- "Which clients have SEO?" / "Show me all clients on AI Assist."
CREATE INDEX client_services_code_idx
    ON client_services (service_code);

-- Only one current contract per (client, service, locale).
CREATE UNIQUE INDEX client_services_current_unique
    ON client_services (client_id, service_code, locale_code)
    WHERE end_date = '9999-12-31';

-- Billing roll-up: leads + monthly fees for active clients.
CREATE INDEX client_services_active_billing_idx
    ON client_services (client_id, fee_basis)
    WHERE end_date = '9999-12-31'
      AND fee_basis IN ('per_lead', 'monthly');

-- Audit trail.
CREATE INDEX client_services_history_idx
    ON client_services (client_id, service_code, start_date DESC);

-- Locale-keyed reporting: "what does this client pay for AR?"
CREATE INDEX client_services_locale_idx
    ON client_services (locale_code)
    WHERE end_date = '9999-12-31';

-- Enforce "wildcard XOR specific-locale" invariant. A client with
-- locale_code='*' for lead_qualification cannot also have locale_code='en'.
-- A client with locale_code='en' cannot later add locale_code='*'.
-- Either pattern is fine on its own; the mix is rejected.
CREATE OR REPLACE FUNCTION forbid_wildcard_locale_mix()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.locale_code = '*' THEN
        IF EXISTS (
            SELECT 1 FROM client_services
            WHERE client_id    = NEW.client_id
              AND service_code = NEW.service_code
              AND locale_code <> '*'
              AND end_date     = '9999-12-31'
              AND client_service_id <> COALESCE(
                  NEW.client_service_id,
                  '00000000-0000-0000-0000-000000000000'::uuid
              )
        ) THEN
            RAISE EXCEPTION
                'client_services: cannot add wildcard locale when specific-locale rows exist for client_id=%, service_code=%',
                NEW.client_id, NEW.service_code;
        END IF;
    ELSE
        IF EXISTS (
            SELECT 1 FROM client_services
            WHERE client_id    = NEW.client_id
              AND service_code = NEW.service_code
              AND locale_code  = '*'
              AND end_date     = '9999-12-31'
        ) THEN
            RAISE EXCEPTION
                'client_services: cannot add specific-locale row when wildcard exists for client_id=%, service_code=%',
                NEW.client_id, NEW.service_code;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER client_services_no_wildcard_mix
    BEFORE INSERT OR UPDATE ON client_services
    FOR EACH ROW
    EXECUTE FUNCTION forbid_wildcard_locale_mix();

-- =============================================================
-- 13. Pricing Discounts
-- =============================================================
CREATE TABLE pricing_discounts (
    pricing_discount_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    discount_type        TEXT NOT NULL
                         CHECK (discount_type IN ('volume','agency_tier','negotiated')),
    tier_id              SMALLINT REFERENCES pricing_tiers(tier_id) ON DELETE RESTRICT,
    client_id            UUID REFERENCES clients(client_id) ON DELETE CASCADE,
    country_id           SMALLINT REFERENCES countries(country_id) ON DELETE RESTRICT,
    segment_id           SMALLINT REFERENCES segments(segment_id) ON DELETE RESTRICT,
    field_name           TEXT,
    leads_min            INT,
    leads_max            INT,
    discount_pct         NUMERIC(5,2) NOT NULL,
    label                TEXT NOT NULL,
    reason               TEXT,
    start_date           DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date),
    CHECK (discount_pct >= 0 AND discount_pct <= 100),
    CHECK (leads_min IS NULL OR leads_min >= 0),
    CHECK (leads_max IS NULL OR leads_max >= leads_min),
    CHECK (
        (discount_type = 'volume' AND tier_id IS NULL AND country_id IS NULL AND segment_id IS NULL AND field_name IS NULL AND leads_min IS NOT NULL AND leads_max IS NOT NULL)
        OR
        (discount_type = 'agency_tier' AND tier_id IS NULL AND client_id IS NULL AND segment_id IS NULL AND field_name IS NULL AND leads_min IS NOT NULL AND leads_max IS NOT NULL)
        OR
        (discount_type = 'negotiated' AND tier_id IS NULL AND client_id IS NOT NULL AND segment_id IS NOT NULL AND field_name IS NOT NULL AND leads_min IS NULL AND leads_max IS NULL AND reason IS NOT NULL)
    )
);
CREATE INDEX pricing_discounts_active_idx  ON pricing_discounts (start_date, end_date);
CREATE INDEX pricing_discounts_type_idx    ON pricing_discounts (discount_type);
CREATE INDEX pricing_discounts_client_idx  ON pricing_discounts (client_id);
CREATE INDEX pricing_discounts_country_idx ON pricing_discounts (country_id);
CREATE INDEX pricing_discounts_segment_idx ON pricing_discounts (segment_id);
CREATE INDEX pricing_discounts_field_idx   ON pricing_discounts (field_name);
CREATE INDEX pricing_discounts_lookup_idx  ON pricing_discounts (client_id, country_id, segment_id, discount_type, leads_min, leads_max, start_date) WHERE end_date = '9999-12-31';
CREATE UNIQUE INDEX pricing_discounts_volume_unique ON pricing_discounts (discount_type, leads_min, leads_max, start_date) WHERE client_id IS NULL AND country_id IS NULL AND segment_id IS NULL;
CREATE UNIQUE INDEX pricing_discounts_client_volume_unique ON pricing_discounts (client_id, discount_type, leads_min, leads_max, start_date) WHERE client_id IS NOT NULL AND discount_type = 'volume';
CREATE UNIQUE INDEX pricing_discounts_agency_unique ON pricing_discounts (country_id, discount_type, leads_min, leads_max, start_date) WHERE client_id IS NULL AND segment_id IS NULL AND discount_type = 'agency_tier';
CREATE UNIQUE INDEX pricing_discounts_client_field_unique ON pricing_discounts (client_id, segment_id, field_name) WHERE client_id IS NOT NULL AND field_name IS NOT NULL AND end_date = '9999-12-31';

-- =============================================================
-- 14. Client Messages
-- =============================================================
CREATE TABLE client_messages (
    client_message_id   UUID PRIMARY KEY,
    client_id           UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    message_text        JSONB NOT NULL,
    start_date          DATE NOT NULL DEFAULT '1900-01-01',
    end_date            DATE NOT NULL DEFAULT '9999-12-31',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (client_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (jsonb_typeof(message_text) = 'object')
);
CREATE INDEX client_messages_client_idx ON client_messages (client_id);
CREATE INDEX client_messages_active_idx ON client_messages (start_date, end_date);
CREATE UNIQUE INDEX client_messages_current_unique ON client_messages (client_id) WHERE end_date = '9999-12-31';

-- =============================================================
-- 15. Ads
-- =============================================================
CREATE TABLE ads (
    ad_id               UUID PRIMARY KEY,
    source_ad_id        TEXT,
    client_id           UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    ad_name             TEXT NOT NULL,
    is_placeholder      BOOLEAN NOT NULL DEFAULT FALSE,
    email_to            TEXT,
    email_cc            TEXT,
    email_bcc           TEXT,
    sms_numbers         JSONB NOT NULL DEFAULT '{}'::jsonb,
    reuse_ad_id         UUID REFERENCES ads(ad_id) ON DELETE RESTRICT,
    language_id         SMALLINT REFERENCES languages(language_id) ON DELETE RESTRICT,
    reopen_policy       TEXT CHECK (reopen_policy IN ('reopen','prompt','forward')),
    start_date          DATE NOT NULL DEFAULT '1900-01-01',
    end_date            DATE NOT NULL DEFAULT '9999-12-31',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (reuse_ad_id IS NULL OR reuse_ad_id <> ad_id),
    CHECK (start_date <= end_date),
    UNIQUE (client_id, source_ad_id)
);
CREATE INDEX ads_client_idx      ON ads (client_id);
CREATE INDEX ads_source_idx      ON ads (source_ad_id) WHERE source_ad_id IS NOT NULL;
CREATE INDEX ads_reuse_ad_idx    ON ads (reuse_ad_id);
CREATE INDEX ads_active_idx      ON ads (start_date, end_date);
CREATE INDEX ads_language_idx    ON ads (language_id);
CREATE INDEX ads_placeholder_idx ON ads (client_id, is_placeholder) WHERE is_placeholder = TRUE;
CREATE INDEX ads_sms_numbers_idx ON ads USING gin (sms_numbers);

-- =============================================================
-- 16. Ad Confirmations
-- =============================================================
CREATE TABLE ad_confirmations (
    ad_confirmation_id  UUID PRIMARY KEY,
    ad_id               UUID NOT NULL REFERENCES ads(ad_id) ON DELETE CASCADE,
    message_text        JSONB NOT NULL,
    start_date          DATE NOT NULL DEFAULT '1900-01-01',
    end_date            DATE NOT NULL DEFAULT '9999-12-31',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ad_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (jsonb_typeof(message_text) = 'object')
);
CREATE INDEX ad_confirmations_ad_idx     ON ad_confirmations (ad_id);
CREATE INDEX ad_confirmations_active_idx ON ad_confirmations (start_date, end_date);
CREATE UNIQUE INDEX ad_confirmations_current_unique ON ad_confirmations (ad_id) WHERE end_date = '9999-12-31';

-- =============================================================
-- 17. Ad Reopen Prompts
-- =============================================================
CREATE TABLE ad_reopen_prompts (
    ad_reopen_prompt_id   UUID PRIMARY KEY,
    ad_id                 UUID NOT NULL REFERENCES ads(ad_id) ON DELETE CASCADE,
    prompt_text           JSONB NOT NULL,
    reopen_button_title   JSONB NOT NULL,
    forward_button_title  JSONB NOT NULL,
    start_date            DATE NOT NULL DEFAULT '1900-01-01',
    end_date              DATE NOT NULL DEFAULT '9999-12-31',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ad_id, start_date),
    CHECK (start_date <= end_date),
    CHECK (jsonb_typeof(prompt_text) = 'object'),
    CHECK (jsonb_typeof(reopen_button_title) = 'object'),
    CHECK (jsonb_typeof(forward_button_title) = 'object')
);
CREATE INDEX ad_reopen_prompts_ad_idx     ON ad_reopen_prompts (ad_id);
CREATE INDEX ad_reopen_prompts_active_idx ON ad_reopen_prompts (start_date, end_date);
CREATE UNIQUE INDEX ad_reopen_prompts_current_unique ON ad_reopen_prompts (ad_id) WHERE end_date = '9999-12-31';

-- =============================================================
-- 18. FAQs
-- =============================================================
CREATE TABLE faqs (
    faq_id           UUID PRIMARY KEY,
    ad_id            UUID NOT NULL REFERENCES ads(ad_id) ON DELETE CASCADE,
    question_id      SMALLINT NOT NULL,
    question_order   INT NOT NULL,
    question_text    JSONB NOT NULL,
    question_type    TEXT NOT NULL CHECK (question_type IN (
        'free_text','first_name','last_name','business_name',
        'phone_number','email_address','radio','dropdown_single','dropdown_multi'
    )),
    options          JSONB,
    depends_on       JSONB,
    mandatory        BOOLEAN NOT NULL DEFAULT TRUE,
    start_date       DATE NOT NULL DEFAULT '1900-01-01',
    end_date         DATE NOT NULL DEFAULT '9999-12-31',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ad_id, question_id, start_date),
    UNIQUE (ad_id, question_order, start_date),
    CHECK (start_date <= end_date),
    CHECK (jsonb_typeof(question_text) = 'object'),
    CHECK (depends_on IS NULL OR jsonb_typeof(depends_on) = 'object'),
    CHECK (
        (question_type IN ('free_text','first_name','last_name','business_name','phone_number','email_address') AND options IS NULL)
        OR
        (question_type IN ('radio','dropdown_single','dropdown_multi') AND options IS NOT NULL AND jsonb_typeof(options) = 'array' AND jsonb_array_length(options) > 0)
    )
);
CREATE INDEX faqs_ad_order_idx ON faqs (ad_id, question_order);
CREATE INDEX faqs_ad_qid_idx   ON faqs (ad_id, question_id);
CREATE INDEX faqs_active_idx   ON faqs (start_date, end_date);
CREATE UNIQUE INDEX faqs_current_qid_unique ON faqs (ad_id, question_id) WHERE end_date = '9999-12-31';
CREATE UNIQUE INDEX faqs_current_order_unique ON faqs (ad_id, question_order) WHERE end_date = '9999-12-31';

-- =============================================================
-- 19. Customers
-- =============================================================
CREATE TABLE customers (
    customer_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ad_id                UUID NOT NULL REFERENCES ads(ad_id) ON DELETE CASCADE,
    demo_session_id      UUID REFERENCES demo_sessions(demo_session_id) ON DELETE CASCADE,
    channel              TEXT NOT NULL CHECK (channel IN ('messenger','instagram','tiktok','chat')),
    channel_user_id      TEXT NOT NULL,
    status               TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN (
        'Pending','Contacted','Qualified','Not-Qualified','No-Response',
        'Bad-Contact','Duplicate','Callback-Requested','Withdrawn','Converted'
    )),
    qualification_score  INT,
    qualification_id     UUID,
    qualification_count  INT NOT NULL DEFAULT 0,
    first_qualified_at   TIMESTAMPTZ,
    last_qualified_at    TIMESTAMPTZ,
    ip_hash              VARCHAR(64),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ad_id, channel, channel_user_id)
);
CREATE INDEX customers_ad_status_idx     ON customers (ad_id, status);
CREATE INDEX customers_qualification_idx ON customers (qualification_id);
CREATE INDEX idx_customers_ip_hash       ON customers (ip_hash);
CREATE INDEX customers_demo_session_idx  ON customers (demo_session_id) WHERE demo_session_id IS NOT NULL;

-- =============================================================
-- 20. Conversations
-- =============================================================
CREATE TABLE conversations (
    conversation_id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id                     BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    current_order                   INT,
    state                           TEXT NOT NULL DEFAULT 'active'
                                    CHECK (state IN ('active','completed','abandoned','rate_limited')),
    consecutive_invalid_answers     INT NOT NULL DEFAULT 0,
    completed_at                    TIMESTAMPTZ,
    reopened_from_conversation_id   BIGINT REFERENCES conversations(conversation_id) ON DELETE SET NULL,
    awaiting_reopen_response        BOOLEAN NOT NULL DEFAULT FALSE,
    language_id                     SMALLINT REFERENCES languages(language_id) ON DELETE RESTRICT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX conversations_customer_idx ON conversations (customer_id, created_at DESC);
CREATE INDEX conversations_state_idx    ON conversations (state);
CREATE INDEX conversations_language_idx ON conversations (language_id);

-- =============================================================
-- 21. Answers
-- =============================================================
CREATE TABLE answers (
    answer_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id  BIGINT NOT NULL REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    faq_id           UUID NOT NULL REFERENCES faqs(faq_id) ON DELETE CASCADE,
    answer_text      TEXT,
    answer_values    JSONB,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (conversation_id, faq_id),
    CHECK (answer_text IS NOT NULL OR answer_values IS NOT NULL),
    CHECK (answer_values IS NULL OR jsonb_typeof(answer_values) = 'array')
);
CREATE INDEX answers_conversation_idx ON answers (conversation_id);
CREATE INDEX answers_faq_idx          ON answers (faq_id);

-- =============================================================
-- 22. Qualification Levels
-- =============================================================
CREATE TABLE qualification_levels (
    qualification_level_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    level_code             TEXT NOT NULL,
    language_id            SMALLINT NOT NULL REFERENCES languages(language_id) ON DELETE RESTRICT,
    label                  TEXT NOT NULL,
    start_date             DATE NOT NULL DEFAULT '1900-01-01',
    end_date               DATE NOT NULL DEFAULT '9999-12-31',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (level_code, language_id, start_date),
    CHECK (start_date <= end_date)
);
CREATE INDEX qualification_levels_code_idx     ON qualification_levels (level_code);
CREATE INDEX qualification_levels_language_idx ON qualification_levels (language_id);
CREATE INDEX qualification_levels_active_idx   ON qualification_levels (start_date, end_date);

-- =============================================================
-- 23. Qualification Score
-- =============================================================
CREATE TABLE qualification_score (
    qualification_score_id  UUID PRIMARY KEY,
    ad_id                   UUID NOT NULL REFERENCES ads(ad_id) ON DELETE CASCADE,
    score                   INT4RANGE NOT NULL,
    level_code              TEXT NOT NULL,
    start_date              DATE NOT NULL DEFAULT '1900-01-01',
    end_date                DATE NOT NULL DEFAULT '9999-12-31',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (ad_id, level_code, start_date),
    CHECK (start_date <= end_date),
    CHECK (NOT isempty(score))
);
CREATE INDEX qualification_score_ad_idx     ON qualification_score (ad_id);
CREATE INDEX qualification_score_active_idx ON qualification_score (start_date, end_date);
CREATE UNIQUE INDEX qualification_score_current_unique ON qualification_score (ad_id, level_code) WHERE end_date = '9999-12-31';
ALTER TABLE qualification_score ADD CONSTRAINT qualification_score_no_overlap EXCLUDE USING gist (ad_id WITH =, score WITH &&) WHERE (end_date = '9999-12-31');
ALTER TABLE customers ADD CONSTRAINT customers_qualification_fk FOREIGN KEY (qualification_id) REFERENCES qualification_score(qualification_score_id) ON DELETE SET NULL;

-- =============================================================
-- 24. Qualifications
-- =============================================================
CREATE TABLE qualifications (
    qualification_event_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id         BIGINT NOT NULL UNIQUE REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    customer_id             BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    ad_id                   UUID NOT NULL REFERENCES ads(ad_id) ON DELETE CASCADE,
    qualification_score     INT NOT NULL,
    qualification_id        UUID REFERENCES qualification_score(qualification_score_id) ON DELETE SET NULL,
    qualified_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX qualifications_customer_idx     ON qualifications (customer_id, qualified_at DESC);
CREATE INDEX qualifications_ad_idx           ON qualifications (ad_id, qualified_at DESC);
CREATE INDEX qualifications_qualified_at_idx ON qualifications (qualified_at);

-- =============================================================
-- 25. Client Users
-- =============================================================
CREATE TABLE client_users (
    client_user_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id            UUID REFERENCES clients(client_id) ON DELETE CASCADE,
    google_sub           TEXT NULL, -- ALLOW NULL FOR PENDING INVITES
    email                TEXT NOT NULL,
    display_name         TEXT,
    role                 TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('owner','admin','viewer')),
    deactivation_reason  TEXT,
    last_login_at        TIMESTAMPTZ,
    start_date           DATE NOT NULL DEFAULT '1900-01-01',
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (google_sub),
    CHECK (start_date <= end_date)
);
CREATE INDEX client_users_client_idx ON client_users (client_id);
CREATE INDEX client_users_active_idx ON client_users (client_id, start_date, end_date);
CREATE UNIQUE INDEX client_users_email_unique ON client_users (lower(email));

-- =============================================================
-- 26. Agency Users
-- =============================================================
CREATE TABLE agency_users (
    agency_user_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agency_id            UUID NOT NULL REFERENCES agencies(agency_id) ON DELETE CASCADE,
    google_sub           TEXT NULL, -- ALLOW NULL FOR PENDING INVITES
    email                TEXT NOT NULL,
    display_name         TEXT,
    role                 TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('owner','admin','viewer')),
    deactivation_reason  TEXT,
    last_login_at        TIMESTAMPTZ,
    start_date           DATE NOT NULL DEFAULT '1900-01-01',
    end_date             DATE NOT NULL DEFAULT '9999-12-31',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (google_sub),
    CHECK (start_date <= end_date)
);
CREATE INDEX agency_users_agency_idx ON agency_users (agency_id);
CREATE INDEX agency_users_active_idx ON agency_users (agency_id, start_date, end_date);
CREATE UNIQUE INDEX agency_users_email_unique ON agency_users (lower(email));

-- =============================================================
-- 27. Customer Statuses
-- =============================================================
CREATE TABLE customer_statuses (
    customer_status_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id        BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    status             TEXT NOT NULL CHECK (status IN ('Pending','Contacted','Qualified','Not-Qualified','No-Response','Bad-Contact','Duplicate','Callback-Requested','Withdrawn','Converted')),
    client_user_id     BIGINT REFERENCES client_users(client_user_id) ON DELETE SET NULL,
    agency_user_id     BIGINT REFERENCES agency_users(agency_user_id) ON DELETE SET NULL,
    note               TEXT,
    changed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (client_user_id IS NULL OR agency_user_id IS NULL)
);
CREATE INDEX customer_statuses_customer_idx    ON customer_statuses (customer_id, changed_at DESC);
CREATE INDEX customer_statuses_changed_at_idx  ON customer_statuses (changed_at);
CREATE INDEX customer_statuses_client_user_idx ON customer_statuses (client_user_id);
CREATE INDEX customer_statuses_agency_user_idx ON customer_statuses (agency_user_id);

-- =============================================================
-- 28. Message Rate Limits
-- =============================================================
CREATE TABLE message_rate_limits (
    channel          TEXT NOT NULL,
    channel_user_id  TEXT NOT NULL,
    window_start     TIMESTAMPTZ NOT NULL,
    window_seconds   INT NOT NULL,
    message_count    INT NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (channel, channel_user_id, window_start, window_seconds)
);
CREATE INDEX message_rate_limits_cleanup_idx ON message_rate_limits (window_start);

-- =============================================================
-- 29. Invoice Payments
-- =============================================================
CREATE TABLE invoice_payments (
    invoice_payment_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id             UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    invoice_number        TEXT NOT NULL,
    invoice_date          DATE NOT NULL,
    billing_period_start  DATE NOT NULL,
    billing_period_end    DATE NOT NULL,
    subtotal              NUMERIC(10,2) NOT NULL,
    vat_amount            NUMERIC(10,2) NOT NULL DEFAULT 0,
    total_amount          NUMERIC(10,2) NOT NULL,
    paid_date             DATE,
    paid_amount           NUMERIC(10,2),
    payment_method        TEXT CHECK (payment_method IN ('eft','card','paypal','other')),
    payment_reference     TEXT,
    status                TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid','paid','partially_paid','disputed','written_off')),
    notes                 TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (billing_period_start <= billing_period_end),
    CHECK (subtotal >= 0),
    CHECK (vat_amount >= 0),
    CHECK (total_amount >= 0),
    CHECK (total_amount = subtotal + vat_amount),
    CHECK (paid_amount IS NULL OR paid_amount >= 0),
    CHECK (paid_date IS NULL OR paid_date >= invoice_date),
    CHECK (paid_amount IS NULL OR paid_amount <= total_amount),
    UNIQUE (client_id, invoice_number)
);
CREATE INDEX invoice_payments_client_idx       ON invoice_payments (client_id);
CREATE INDEX invoice_payments_invoice_date_idx ON invoice_payments (invoice_date DESC);
CREATE INDEX invoice_payments_paid_date_idx    ON invoice_payments (paid_date) WHERE paid_date IS NOT NULL;
CREATE INDEX invoice_payments_unpaid_idx       ON invoice_payments (client_id, invoice_date) WHERE paid_date IS NULL AND status IN ('unpaid', 'partially_paid');
CREATE UNIQUE INDEX invoice_payments_one_per_period ON invoice_payments (client_id, billing_period_start, billing_period_end);

-- =============================================================
-- 30. Contacts
-- =============================================================
CREATE TABLE contacts (
    contact_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    submission_id   UUID NOT NULL UNIQUE,
    name            TEXT NOT NULL,
    email           TEXT NOT NULL,
    company         TEXT,
    phone           TEXT,
    enquiry         TEXT,
    message         TEXT NOT NULL,
    consent         BOOLEAN NOT NULL,
    locale          VARCHAR(5),
    ip_hash         TEXT,
    user_agent      TEXT,
    referer         TEXT,
    submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    replied_at      TIMESTAMPTZ,
    status          TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','read','replied','archived','spam')),
    honeypot_hit    BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (replied_at IS NULL OR replied_at >= submitted_at)
);
CREATE INDEX contacts_submitted_idx  ON contacts (submitted_at DESC);
CREATE INDEX contacts_status_idx     ON contacts (status, submitted_at DESC);
CREATE INDEX contacts_email_idx      ON contacts (lower(email));
CREATE INDEX contacts_ip_hash_idx    ON contacts (ip_hash) WHERE ip_hash IS NOT NULL;
CREATE INDEX contacts_enquiry_idx    ON contacts (enquiry) WHERE enquiry IS NOT NULL;

-- =============================================================
-- 31. Live Chat Logs
-- =============================================================
CREATE TABLE live_chat_logs (
    log_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    submission_id   UUID NOT NULL UNIQUE,
    client_id       UUID NOT NULL,
    ad_id           UUID NOT NULL,
    demo_session_id UUID REFERENCES demo_sessions(demo_session_id) ON DELETE CASCADE,
    session_id      TEXT NOT NULL,
    question        TEXT NOT NULL,
    answer          TEXT,
    locale          VARCHAR(5) NOT NULL DEFAULT 'en',
    ip_hash         VARCHAR(64),
    utm_source      VARCHAR(100),
    utm_medium      VARCHAR(100),
    utm_campaign    VARCHAR(100),
    section_path    TEXT,
    status          TEXT NOT NULL DEFAULT 'success',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX live_chat_logs_client_idx ON live_chat_logs (client_id, created_at DESC);
CREATE INDEX live_chat_logs_ad_idx ON live_chat_logs (ad_id, created_at DESC);
CREATE INDEX live_chat_logs_ip_idx ON live_chat_logs (ip_hash, created_at DESC) WHERE ip_hash IS NOT NULL;
CREATE INDEX live_chat_logs_demo_session_idx ON live_chat_logs (demo_session_id) WHERE demo_session_id IS NOT NULL;

-- =============================================================
-- 32. Settings (Live Chat & Operational Settings)
-- =============================================================
CREATE TABLE settings (
    setting_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    setting_key    TEXT NOT NULL UNIQUE,
    setting_value  TEXT NOT NULL,
    setting_type   TEXT NOT NULL DEFAULT 'number' CHECK (setting_type IN ('number','boolean','integer','string')),
    description    TEXT,
    start_date     DATE NOT NULL DEFAULT '1900-01-01',
    end_date       DATE NOT NULL DEFAULT '9999-12-31',
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (start_date <= end_date)
);
CREATE INDEX settings_active_idx ON settings (start_date, end_date);
CREATE UNIQUE INDEX settings_key_active_idx ON settings (setting_key) WHERE end_date = '9999-12-31';

-- =============================================================
-- 33. Triggers
-- =============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER conversations_updated_at BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER client_users_updated_at BEFORE UPDATE ON client_users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER agency_users_updated_at BEFORE UPDATE ON agency_users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER invoice_payments_updated_at BEFORE UPDATE ON invoice_payments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER settings_updated_at BEFORE UPDATE ON settings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION sync_customer_current_status()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE customers SET status = NEW.status, updated_at = now() WHERE customer_id = NEW.customer_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER customer_statuses_sync_current AFTER INSERT ON customer_statuses FOR EACH ROW EXECUTE FUNCTION sync_customer_current_status();

-- =============================================================
-- 34. Reuse-chain guard
-- =============================================================
CREATE OR REPLACE FUNCTION forbid_content_on_leaf_ad()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM ads WHERE ad_id = NEW.ad_id AND reuse_ad_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Table % rows must live on the root ad; ad_id % is a leaf (reuse_ad_id IS NOT NULL)', TG_TABLE_NAME, NEW.ad_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER qualification_score_root_only BEFORE INSERT OR UPDATE ON qualification_score FOR EACH ROW EXECUTE FUNCTION forbid_content_on_leaf_ad();
CREATE TRIGGER faqs_root_only BEFORE INSERT OR UPDATE ON faqs FOR EACH ROW EXECUTE FUNCTION forbid_content_on_leaf_ad();
CREATE TRIGGER ad_confirmations_root_only BEFORE INSERT OR UPDATE ON ad_confirmations FOR EACH ROW EXECUTE FUNCTION forbid_content_on_leaf_ad();
CREATE TRIGGER ad_reopen_prompts_root_only BEFORE INSERT OR UPDATE ON ad_reopen_prompts FOR EACH ROW EXECUTE FUNCTION forbid_content_on_leaf_ad();

-- =============================================================
-- 35. effective_ad_id()
-- =============================================================
CREATE OR REPLACE FUNCTION effective_ad_id(p_source_ad_id TEXT)
RETURNS UUID
LANGUAGE SQL
STABLE
AS $$
    WITH RECURSIVE chain AS (
        SELECT ad_id, reuse_ad_id, 0 AS depth FROM ads WHERE source_ad_id = p_source_ad_id
        UNION ALL
        SELECT a.ad_id, a.reuse_ad_id, c.depth + 1 FROM ads a JOIN chain c ON a.ad_id = c.reuse_ad_id WHERE c.depth < 5
    )
    SELECT ad_id FROM chain WHERE reuse_ad_id IS NULL LIMIT 1;
$$;

-- =============================================================
-- 36. Active views
-- =============================================================
CREATE VIEW active_languages AS SELECT * FROM languages WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_currencies AS SELECT * FROM currencies WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_countries AS SELECT * FROM countries WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_segments AS SELECT * FROM segments WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_messages AS SELECT * FROM messages WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_tiers AS SELECT * FROM pricing_tiers WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_segment_tiers AS SELECT * FROM pricing_segment_tiers WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_rates AS SELECT * FROM pricing_rates WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_website AS SELECT * FROM pricing_website WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_addons AS SELECT * FROM pricing_addons WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_pilot AS SELECT * FROM pricing_pilot WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_pricing_discounts AS SELECT * FROM pricing_discounts WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_agencies AS SELECT * FROM agencies WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_clients AS SELECT * FROM clients WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_client_messages AS SELECT * FROM client_messages WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_ads AS SELECT * FROM ads WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_ad_confirmations AS SELECT * FROM ad_confirmations WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_ad_reopen_prompts AS SELECT * FROM ad_reopen_prompts WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_faqs AS SELECT * FROM faqs WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_qualification_levels AS SELECT * FROM qualification_levels WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_qualification_score AS SELECT * FROM qualification_score WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_agency_users AS SELECT * FROM agency_users WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_client_users AS SELECT * FROM client_users WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;
CREATE VIEW active_settings AS SELECT * FROM settings WHERE start_date <= CURRENT_DATE AND CURRENT_DATE <= end_date;

CREATE VIEW active_ads_with_active_clients AS
SELECT a.* FROM active_ads a JOIN active_clients c ON c.client_id = a.client_id;

CREATE VIEW active_ads_with_merged_emails AS
SELECT
    a.ad_id, a.client_id, a.ad_name, a.source_ad_id, a.language_id,
    COALESCE(a.email_to, c.email_to) AS email_to,
    COALESCE(a.email_cc, c.email_cc) AS email_cc,
    COALESCE(a.email_bcc, c.email_bcc) AS email_bcc,
    c.sms_numbers || a.sms_numbers AS sms_numbers,
    a.start_date, a.end_date
FROM active_ads a
JOIN active_clients c ON c.client_id = a.client_id;

-- =============================================================
-- 37. Live Chat by Question View
-- =============================================================
CREATE VIEW v_live_chat_by_question AS
WITH
answered AS (
    SELECT f.ad_id, f.question_order, count(DISTINCT ans.conversation_id) AS answered
    FROM answers ans
    JOIN active_faqs f ON f.faq_id = ans.faq_id
    JOIN conversations c ON c.conversation_id = ans.conversation_id
    WHERE c.state IN ('completed', 'abandoned', 'rate_limited')
    GROUP BY f.ad_id, f.question_order
),
abandoned AS (
    SELECT cu.ad_id, c.current_order AS question_order, count(DISTINCT c.conversation_id) AS abandoned
    FROM conversations c
    JOIN customers cu ON cu.customer_id = c.customer_id
    WHERE c.state = 'abandoned' AND c.current_order IS NOT NULL
    GROUP BY cu.ad_id, c.current_order
)
SELECT
    a.client_id, f.ad_id, f.question_order, f.question_text->>'en' AS question_en, f.question_type,
    COALESCE(ans.answered, 0) AS completions, COALESCE(abn.abandoned, 0) AS abandons,
    COALESCE(ans.answered, 0) + COALESCE(abn.abandoned, 0) AS attempts,
    round(100.0 * COALESCE(abn.abandoned, 0) / nullif(COALESCE(ans.answered, 0) + COALESCE(abn.abandoned, 0), 0), 1) AS abandon_pct
FROM active_ads a
JOIN active_faqs f ON f.ad_id = a.ad_id
LEFT JOIN answered ans ON ans.ad_id = f.ad_id AND ans.question_order = f.question_order
LEFT JOIN abandoned abn ON abn.ad_id = f.ad_id AND abn.question_order = f.question_order
WHERE COALESCE(ans.answered, 0) + COALESCE(abn.abandoned, 0) > 0
ORDER BY a.client_id, f.ad_id, f.question_order;

-- =============================================================
-- 38. Live Chat Funnel View
-- =============================================================
CREATE OR REPLACE VIEW v_live_chat_funnel AS
SELECT client_id, ad_id, date_trunc('day', created_at)::date AS day, status, count(*) AS messages
FROM live_chat_logs
GROUP BY client_id, ad_id, day, status;

-- =============================================================
-- 39. Live Chat Drop-Off View
-- =============================================================
CREATE OR REPLACE VIEW v_live_chat_dropoff AS
WITH per_ad AS (
    SELECT client_id, ad_id, status, count(*) AS n
    FROM live_chat_logs
    WHERE created_at > now() - interval '30 days'
    GROUP BY client_id, ad_id, status
)
SELECT client_id, ad_id, status, n, round(100.0 * n / nullif(sum(n) OVER (PARTITION BY client_id, ad_id), 0), 1) AS pct
FROM per_ad
ORDER BY client_id, ad_id, n DESC;

-- =============================================================
-- 40. Active Client Services View
-- =============================================================
CREATE VIEW active_client_services AS
SELECT *
FROM client_services
WHERE start_date <= CURRENT_DATE
  AND CURRENT_DATE <= end_date;

COMMIT;
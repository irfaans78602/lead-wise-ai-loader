-- =============================================================
-- 20-seed-base-website.sql
-- Base reference data for the LeadWise AI platform.
-- Run after 10-schema-website.sql.
-- Run BEFORE 30/40/50 (pricing).
-- Safe to re-run: all inserts and updates are idempotent.
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Languages
-- =============================================================
INSERT INTO languages (code, name, native_name) VALUES
    ('en', 'English', 'English'),
    ('ar', 'Arabic',  'العربية'),
    ('es', 'Spanish', 'Español'),
    ('fr', 'French',  'Français'),
    ('zh', 'Chinese', '中文')
ON CONFLICT (code) DO NOTHING;

-- =============================================================
-- 2. Currencies
-- =============================================================
INSERT INTO currencies (code, name, symbol, minor_unit) VALUES
    ('ZAR', 'South African Rand', 'R', 2),
    ('USD', 'US Dollar',          '$', 2),
    ('GBP', 'British Pound',      '£', 2)
ON CONFLICT (code) DO NOTHING;

-- =============================================================
-- 3. Countries
-- =============================================================
INSERT INTO countries (code, name, default_language_id, default_currency_id)
SELECT v.code, v.name, l.language_id, c.currency_id
FROM (VALUES
    ('ZA', 'South Africa',   'en', 'ZAR'),
    ('GB', 'United Kingdom', 'en', 'GBP'),
    ('US', 'United States',  'en', 'USD')
) AS v(code, name, lang_code, curr_code)
JOIN languages  l ON l.code = v.lang_code
JOIN currencies c ON c.code = v.curr_code
ON CONFLICT (code) DO NOTHING;

-- =============================================================
-- 4. Segments
-- =============================================================
INSERT INTO segments (code, name) VALUES
    ('trades_home_services',    'Trades & Home Services'),
    ('beauty_personal_care',    'Beauty & Personal Care'),
    ('pet_services',            'Pet Services'),
    ('hospitality_bookings',    'Hospitality & Bookings'),
    ('fitness_coaching',        'Fitness & Coaching'),
    ('education_training',      'Education & Training'),
    ('professional_services',   'Professional Services'),
    ('automotive',              'Automotive'),
    ('retail_ecommerce',        'Retail & E-commerce'),
    ('health_wellness',         'Health & Wellness'),
    ('high_ticket_services',    'High-Ticket Services'),
    ('real_estate',             'Real Estate'),
    ('b2b_enterprise',          'B2B / Enterprise'),
    ('financial_services',      'Financial Services'),
    ('legal_services',          'Legal Services'),
    ('travel_tourism',          'Travel & Tourism'),
    ('logistics_transport',     'Logistics & Transport'),
    ('agriculture_farming',     'Agriculture & Farming'),
    ('events_entertainment',    'Events & Entertainment'),
    ('non_profit_ngo',          'Non-Profit / NGO'),
    ('franchise_groups',        'Franchise Groups'),
    ('saas_it',                 'SaaS, IT & Technology'),
    ('other_bespoke',           'Other / Bespoke')
ON CONFLICT (code) DO NOTHING;

-- =============================================================
-- 5. Qualification Levels
-- =============================================================
INSERT INTO qualification_levels (level_code, language_id, label)
SELECT v.level_code, l.language_id, v.label
FROM (VALUES
    ('low',       'en', 'Low'),
    ('medium',    'en', 'Medium'),
    ('high',      'en', 'High'),
    ('very_high', 'en', 'Very High'),
    ('low',       'ar', 'منخفض'),
    ('medium',    'ar', 'متوسط'),
    ('high',      'ar', 'مرتفع'),
    ('very_high', 'ar', 'مرتفع جداً'),
    ('low',       'es', 'Bajo'),
    ('medium',    'es', 'Medio'),
    ('high',      'es', 'Alto'),
    ('very_high', 'es', 'Muy alto'),
    ('low',       'fr', 'Faible'),
    ('medium',    'fr', 'Moyen'),
    ('high',      'fr', 'Élevé'),
    ('very_high', 'fr', 'Très élevé'),
    ('low',       'zh', '低'),
    ('medium',    'zh', '中'),
    ('high',      'zh', '高'),
    ('very_high', 'zh', '非常高')
) AS v(level_code, lang_code, label)
JOIN languages l ON l.code = v.lang_code
ON CONFLICT (level_code, language_id, start_date) DO NOTHING;

-- =============================================================
-- 6. Messages — customer_status_labels
-- =============================================================
INSERT INTO messages (message_code, message_text, description)
VALUES (
    'customer_status_labels',
    '{
        "en": {
            "Pending":            "Pending",
            "Contacted":          "Contacted",
            "Qualified":          "Qualified",
            "Not-Qualified":      "Not-Qualified",
            "No-Response":        "No Response",
            "Bad-Contact":        "Bad Contact",
            "Duplicate":          "Duplicate",
            "Callback-Requested": "Callback Requested",
            "Withdrawn":          "Withdrawn",
            "Converted":          "Converted"
        },
        "ar": {
            "Pending":            "معلق",
            "Contacted":          "تم التواصل",
            "Qualified":          "مؤهَّل",
            "Not-Qualified":      "غير مؤهَّل",
            "No-Response":        "لا يوجد رد",
            "Bad-Contact":        "بيانات اتصال خاطئة",
            "Duplicate":          "مكرَّر",
            "Callback-Requested": "طلب معاودة الاتصال",
            "Withdrawn":          "منسحب",
            "Converted":          "مُحوَّل"
        },
        "es": {
            "Pending":            "Pendiente",
            "Contacted":          "Contactado",
            "Qualified":          "Cualificado",
            "Not-Qualified":      "No cualificado",
            "No-Response":        "Sin respuesta",
            "Bad-Contact":        "Contacto incorrecto",
            "Duplicate":          "Duplicado",
            "Callback-Requested": "Solicitud de devolución de llamada",
            "Withdrawn":          "Retirado",
            "Converted":          "Convertido"
        },
        "fr": {
            "Pending":            "En attente",
            "Contacted":          "Contacté",
            "Qualified":          "Qualifié",
            "Not-Qualified":      "Non qualifié",
            "No-Response":        "Sans réponse",
            "Bad-Contact":        "Coordonnées erronées",
            "Duplicate":          "Doublon",
            "Callback-Requested": "Rappel demandé",
            "Withdrawn":          "Retiré",
            "Converted":          "Converti"
        },
        "zh": {
            "Pending":            "待处理",
            "Contacted":          "已联系",
            "Qualified":          "已合格",
            "Not-Qualified":      "未合格",
            "No-Response":        "无回复",
            "Bad-Contact":        "联系方式错误",
            "Duplicate":          "重复",
            "Callback-Requested": "请求回电",
            "Withdrawn":          "已撤回",
            "Converted":          "已转化"
        }
    }'::jsonb,
    'Dashboard labels for customers.status and customer_statuses.status, keyed by language code then status code.'
)
ON CONFLICT (message_code) DO UPDATE
SET message_text = messages.message_text || EXCLUDED.message_text,
    description  = EXCLUDED.description;

-- =============================================================
-- 7. Messages — system prompts
-- =============================================================
INSERT INTO messages (message_code, message_text, description) VALUES
    ('rate_limit',
     '{"en": "I''m having trouble understanding your responses. Let''s pause this conversation for now — feel free to try again later, or contact us directly."}'::jsonb,
     'Sent when a conversation hits the invalid-answer cap'),

    ('invalid_phone',
     '{"en": "That doesn''t look like a valid phone number. Please include your country code, e.g. +27821234567."}'::jsonb,
     'Sent when a phone number answer fails validation'),

    ('invalid_email',
     '{"en": "That doesn''t look like a valid email address, e.g. name@example.com."}'::jsonb,
     'Sent when an email answer fails validation'),

    ('empty_answer',
     '{"en": "Sorry, I didn''t catch that — could you answer again?"}'::jsonb,
     'Sent when a mandatory question receives a blank reply'),

    ('radio_invalid',
     '{"en": "Please choose one of the options below."}'::jsonb,
     'Sent when a radio/dropdown_single answer doesn''t match any option'),

    ('dropdown_multi_invalid',
     '{"en": "I didn''t recognise ''{part}''. Please choose from the options below."}'::jsonb,
     'Sent when one part of a dropdown_multi answer doesn''t match any option'),

    ('unsupported_type',
     '{"en": "Unsupported question type."}'::jsonb,
     'Sent when a faq row has a question_type the engine doesn''t understand'),

    ('suggest_phone',
     '{"en": "Did you mean {part}? If so, please reply with exactly that number."}'::jsonb,
     'Sent when the AI suggests a corrected phone number'),

    ('suggest_email',
     '{"en": "Did you mean {part}? If so, please reply with exactly that address."}'::jsonb,
     'Sent when the AI suggests a corrected email address'),

    ('default_confirmation',
     '{
        "en": "Thank you {10}! That''s everything we need — our team will be in touch shortly.",
        "ar": "شكراً لك {10}! هذا كل ما نحتاجه — سيتواصل معك فريقنا قريباً.",
        "es": "¡Gracias, {10}! Eso es todo lo que necesitamos — nuestro equipo se pondrá en contacto pronto.",
        "fr": "Merci {10} ! C''est tout ce dont nous avons besoin — notre équipe vous contactera bientôt.",
        "zh": "谢谢您，{10}！我们需要的信息已经齐全——我们的团队会尽快与您联系。"
     }'::jsonb,
     'Fallback confirmation sent when an ad has no ad_confirmations row'),

    ('default_closed',
     '{"en": "Thank you for your message. This business is no longer accepting enquiries. We wish you well."}'::jsonb,
     'Fallback closed message sent when a client has no client_messages row'),

    ('default_reopen_prompt',
     '{
        "en": "Thanks for reaching out again, {10}. Your previous enquiry is with our team. Would you like to start a new enquiry?",
        "ar": "شكراً لتواصلك مرة أخرى، {10}. استفسارك السابق قيد المعالجة من قبل فريقنا. هل ترغب في بدء استفسار جديد؟",
        "es": "Gracias por contactarnos de nuevo, {10}. Su consulta anterior está con nuestro equipo. ¿Le gustaría iniciar una nueva consulta?",
        "fr": "Merci de nous avoir recontactés, {10}. Votre demande précédente est entre les mains de notre équipe. Souhaitez-vous commencer une nouvelle demande ?",
        "zh": "感谢您再次联系我们，{10}。您之前的咨询已由我们的团队处理。您想开始新的咨询吗？"
     }'::jsonb,
     'Fallback reopen prompt body, when an ad has no ad_reopen_prompts row'),

    ('default_reopen_button_title',
     '{
        "en": "Yes, start fresh",
        "ar": "نعم، ابدأ من جديد",
        "es": "Sí, empezar de nuevo",
        "fr": "Oui, recommencer",
        "zh": "是的，重新开始"
     }'::jsonb,
     'Fallback label for the reopen button'),

    ('default_forward_button_title',
     '{
        "en": "No, just pass this on",
        "ar": "لا، فقط مرّر هذا",
        "es": "No, solo reenvíelo",
        "fr": "Non, transmettez simplement",
        "zh": "不，只是转达一下"
     }'::jsonb,
     'Fallback label for the forward button')
ON CONFLICT (message_code) DO NOTHING;

-- =============================================================
-- 8. Settings
-- =============================================================
INSERT INTO settings (setting_key, setting_value, setting_type, description) VALUES
    ('agency_discount_pct',       20.0000,  'number',  'Wholesale discount for agencies'),
    ('bundle_bots_seo_pct',       10.0000,  'number',  'Bundle discount: Bots + SEO'),
    ('bundle_bots_seo_ads_pct',   15.0000,  'number',  'Bundle discount: Bots + SEO + Ads'),
    ('bundle_bots_seo_wp_pct',    15.0000,  'number',  'Bundle discount: Bots + SEO + WordPress'),
    ('bundle_full_stack_pct',     20.0000,  'number',  'Bundle discount: all four services'),
    ('pilot_setup_discount_pct', 100.0000,  'number',  'Pilot: setup fee waived'),
    ('pilot_base_discount_pct',   50.0000,  'number',  'Pilot: base fee halved'),
    ('pilot_duration_months',      6.0000,  'number',  'Pilot pricing duration in months'),
    ('max_invalid_answers',        5.0000,  'integer', 'Consecutive invalid answers before rate-limiting'),
    ('rate_limit_cooldown_hours', 24.0000,  'number',  'Cool-down duration after rate limiting'),
    ('rate_limit_window_seconds_1', 60.0000,   'number', 'First rate-limit window (seconds)'),
    ('rate_limit_max_1',             10.0000,  'number', 'Max messages in window 1'),
    ('rate_limit_window_seconds_2', 3600.0000, 'number', 'Second rate-limit window (seconds)'),
    ('rate_limit_max_2',             60.0000,  'number', 'Max messages in window 2'),
    ('rate_limit_window_seconds_3', 86400.0000,'number', 'Third rate-limit window (seconds)'),
    ('rate_limit_max_3',            200.0000,  'number', 'Max messages in window 3'),
    ('rate_limit_cleanup_hours',     48.0000,  'number', 'Prune rate-limit rows older than this')
ON CONFLICT (setting_key) DO NOTHING;

-- =============================================================
-- 9. Pricing Tiers
-- =============================================================
INSERT INTO pricing_tiers (tier_code, tier_name, tier_order, description) VALUES
    ('standard',     'Standard',     1, 'Trades, beauty, pet, non-profit, hospitality, fitness'),
    ('professional', 'Professional', 2, 'Education, professional services, retail, travel'),
    ('high_value',   'High-Value',   3, 'Automotive, health, high-ticket, logistics, agriculture, events, other'),
    ('premium',      'Premium',      4, 'Real estate, B2B, financial, legal, franchise, SaaS')
ON CONFLICT (tier_code) DO NOTHING;

-- =============================================================
-- 10. Pricing Segment Tiers
-- =============================================================
INSERT INTO pricing_segment_tiers (segment_id, tier_id)
SELECT s.segment_id, t.tier_id
FROM (VALUES
    ('trades_home_services',  'standard'),
    ('beauty_personal_care',  'standard'),
    ('pet_services',          'standard'),
    ('non_profit_ngo',        'standard'),
    ('hospitality_bookings',  'standard'),
    ('fitness_coaching',      'standard'),
    ('education_training',    'professional'),
    ('professional_services', 'professional'),
    ('retail_ecommerce',      'professional'),
    ('travel_tourism',        'professional'),
    ('automotive',            'high_value'),
    ('health_wellness',       'high_value'),
    ('high_ticket_services',  'high_value'),
    ('events_entertainment',  'high_value'),
    ('other_bespoke',         'high_value'),
    ('logistics_transport',   'high_value'),
    ('agriculture_farming',   'high_value'),
    ('real_estate',           'premium'),
    ('b2b_enterprise',        'premium'),
    ('financial_services',    'premium'),
    ('legal_services',        'premium'),
    ('saas_it',               'premium'),
    ('franchise_groups',      'premium')
) AS v(segment_code, tier_code)
JOIN segments      s ON s.code = v.segment_code
JOIN pricing_tiers t ON t.tier_code = v.tier_code
ON CONFLICT (segment_id, start_date) DO NOTHING;

-- =============================================================
-- 11. Schema Version
-- =============================================================
INSERT INTO settings (setting_key, setting_value, setting_type, description)
VALUES ('schema_version', 1, 'integer',
        'Loader-expected schema version; compare against EXPECTED_SCHEMA_VERSION')
ON CONFLICT (setting_key) DO UPDATE
SET setting_value = EXCLUDED.setting_value,
    description   = EXCLUDED.description;

-- =============================================================
-- 12. Ask AI Limits
-- =============================================================
INSERT INTO settings (setting_key, setting_value, setting_type, description)
VALUES ('ask_ai_rate_limit_max', 25, 'integer', 'Max questions per IP for Ask AI')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = 25;

INSERT INTO settings (setting_key, setting_value, setting_type, description)
VALUES ('ask_ai_rate_limit_window_minutes', 60, 'integer', 'Time window in minutes for Ask AI rate limit')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = 60;

INSERT INTO settings (setting_key, setting_value, setting_type, description)
VALUES ('ask_ai_chunk_limit', 10, 'integer', 'Number of RAG chunks to retrieve from vector search')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = 10;

-- =============================================================
-- 13. Website Chat Limits
-- =============================================================
INSERT INTO settings (setting_key, setting_value, setting_type, description)
VALUES 
  ('chat_rate_limit_max', 25, 'integer', 'Max messages per IP for Website Chat'),
  ('chat_rate_limit_window_minutes', 60, 'integer', 'Time window in minutes for Website Chat rate limit')
ON CONFLICT (setting_key) DO UPDATE 
SET 
  setting_value = EXCLUDED.setting_value,
  setting_type = EXCLUDED.setting_type;

COMMIT;
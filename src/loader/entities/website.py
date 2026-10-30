"""
entities/website.py
Registry of entity types the loader knows how to write (website DB).
"""

from loader.entities import EntitySpec


# ---------------------------------------------------------------------
# Unversioned
# ---------------------------------------------------------------------

CLIENTS = EntitySpec(
    name="clients",
    table="clients",
    pk_col="client_id",
    pk_kind="client",
    natural_key=("client_id",),
    columns={
        "name": "name",
        "email_to": "email_to",
        "email_cc": "email_cc",
        "email_bcc": "email_bcc",
        "email_from_name": "email_from_name",
        "email_from_prefix": "email_from_prefix",
        "response_time_expectation": "response_time_expectation",
        "sms_numbers": "sms_numbers",
        "country_code": "country_id",
        "segment_code": "segment_id",
        "currency_code": "currency_id",
        "language_code": "language_id",
        "is_platform_owner": "is_platform_owner",
        "is_pilot": "is_pilot",
        "pilot_ends_on": "pilot_ends_on",
        "closed_behavior": "closed_behavior",
        "reopen_policy": "reopen_policy",
        "allowed_origins": "allowed_origins",
        
        # NEW COLUMNS
        "lead_transactions_title": "lead_transactions_title",
        "display_first_name_question_id": "display_first_name_question_id",
        "display_last_name_question_id": "display_last_name_question_id",
        "display_contact_question_id": "display_contact_question_id",
        
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


CLIENT_USERS = EntitySpec(
    name="client_users",
    table="client_users",
    pk_col="google_sub",
    pk_kind="client_user",
    natural_key=("google_sub",),
    columns={
        "client_key": "client_id",
        "email": "email",
        "display_name": "display_name",
        "role": "role",
        "deactivation_reason": "deactivation_reason",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


ADS = EntitySpec(
    name="ads",
    table="ads",
    pk_col="ad_id",
    pk_kind="ad",
    natural_key=("ad_id",),
    columns={
        "source_ad_id": "source_ad_id",
        "ad_name": "ad_name",
        "is_placeholder": "is_placeholder",
        "email_to": "email_to",
        "email_cc": "email_cc",
        "email_bcc": "email_bcc",
        "sms_numbers": "sms_numbers",
        "reopen_policy": "reopen_policy",
        "language_code": "language_id",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


# ---------------------------------------------------------------------
# Versioned content - root-ad-owned
# ---------------------------------------------------------------------

CLIENT_MESSAGES = EntitySpec(
    name="client_messages",
    table="client_messages",
    pk_col="client_message_id",
    pk_kind="client_message",
    natural_key=("client_id",),
    versioned=True,
    version_key=("start_date",),
    columns={
        "message_text": "message_text",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


AD_CONFIRMATIONS = EntitySpec(
    name="ad_confirmations",
    table="ad_confirmations",
    pk_col="ad_confirmation_id",
    pk_kind="ad_confirmation",
    natural_key=("ad_id",),
    versioned=True,
    version_key=("start_date",),
    columns={
        "message_text": "message_text",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


AD_REOPEN_PROMPTS = EntitySpec(
    name="ad_reopen_prompts",
    table="ad_reopen_prompts",
    pk_col="ad_reopen_prompt_id",
    pk_kind="ad_reopen_prompt",
    natural_key=("ad_id",),
    versioned=True,
    version_key=("start_date",),
    columns={
        "prompt_text": "prompt_text",
        "reopen_button_title": "reopen_button_title",
        "forward_button_title": "forward_button_title",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


FAQS = EntitySpec(
    name="faqs",
    table="faqs",
    pk_col="faq_id",
    pk_kind="faq",
    natural_key=("ad_id", "question_id"),
    versioned=True,
    version_key=("start_date",),
    columns={
        "question_id": "question_id",
        "question_order": "question_order",
        "question_text": "question_text",
        "question_type": "question_type",
        "options": "options",
        "depends_on": "depends_on",
        "mandatory": "mandatory",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


QUALIFICATION_SCORE = EntitySpec(
    name="qualification_score",
    table="qualification_score",
    pk_col="qualification_score_id",
    pk_kind="qscore",
    natural_key=("ad_id", "level_code"),
    versioned=True,
    version_key=("start_date",),
    columns={
        "level_code": "level_code",
        "score_range": "score",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


PRICING_DISCOUNTS = EntitySpec(
    name="pricing_discounts",
    table="pricing_discounts",
    pk_col="pricing_discount_id",
    pk_kind="pricing_discount",
    natural_key=("discount_type", "leads_min", "leads_max"),
    columns={
        "discount_type": "discount_type",
        "leads_min": "leads_min",
        "leads_max": "leads_max",
        "country_code": "country_id",
        "segment_code": "segment_id",
        "field_name": "field_name",
        "discount_pct": "discount_pct",
        "label": "label",
        "reason": "reason",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


# ---------------------------------------------------------------------
# Runtime Logs
# ---------------------------------------------------------------------

LIVE_CHAT_LOGS = EntitySpec(
    name="live_chat_logs",
    table="live_chat_logs",
    pk_col="submission_id",
    pk_kind="live_chat_log",
    natural_key=("submission_id",),
    columns={
        "client_key": "client_id",
        "ad_key": "ad_id",
        "session_id": "session_id",
        "question": "question",
        "answer": "answer",
        "locale": "locale",
        "ip_hash": "ip_hash",
        "utm_source": "utm_source",
        "utm_medium": "utm_medium",
        "utm_campaign": "utm_campaign",
        "section_path": "section_path",
        "status": "status",
        "created_at": "created_at",
    },
)


ALL = {
    spec.name: spec
    for spec in (
        CLIENTS,
        CLIENT_USERS,
        ADS,
        CLIENT_MESSAGES,
        AD_CONFIRMATIONS,
        AD_REOPEN_PROMPTS,
        FAQS,
        QUALIFICATION_SCORE,
        PRICING_DISCOUNTS,
        LIVE_CHAT_LOGS,
    )
}
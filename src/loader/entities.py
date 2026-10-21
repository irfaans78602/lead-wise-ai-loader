"""
entities.py
Registry of entity types the loader knows how to write.

Each EntitySpec describes:
  - name:         JSON key the entity lives under
  - table:        Postgres table to write
  - pk_col:       primary key column, or - for tables whose real PK is
                  an IDENTITY the loader never sees - the UNIQUE column
                  used as the row identity across runs
  - pk_kind:      string tag passed to uuid_gen.derive()
  - natural_key:  tuple of PG column names that identify the logical
                  entity (NOT the version PK). For unversioned tables
                  this is the PK. For versioned tables this is the
                  logical key that stays constant across versions.
  - versioned:    True if the table has multiple rows per logical key
  - version_key:  for versioned tables, extra fields that distinguish
                  one version from another (usually "start_date")
  - columns:      JSON field name -> Postgres column name mapping for
                  the mutable payload
  - parent_refs:  JSON field -> (kind, natural_key_field). Resolved at
                  plan time.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class EntitySpec:
    name: str
    table: str
    pk_col: str
    pk_kind: str
    natural_key: tuple[str, ...]
    versioned: bool = False
    version_key: tuple[str, ...] = ()
    columns: dict[str, str] = field(default_factory=dict)
    parent_refs: dict[str, tuple[str, str]] = field(default_factory=dict)


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
        "country_code": "country_id",
        "segment_code": "segment_id",
        "currency_code": "currency_id",
        "language_code": "language_id",
        "is_platform_owner": "is_platform_owner",
        "is_pilot": "is_pilot",
        "pilot_ends_on": "pilot_ends_on",
        "closed_behavior": "closed_behavior",
        "reopen_policy": "reopen_policy",
        "start_date": "start_date",
        "end_date": "end_date",
    },
)


# client_users.client_user_id is IDENTITY - the loader never sees it.
# google_sub is UNIQUE and stable across runs, so it is used as the row
# identity. Everything downstream (preflight, diff, write) keys off
# spec.pk_col, so no other module needs to know about the trick.
#
# client_key (JSON) is mapped to client_id. preflight converts the key
# string to the client's UUID. The schema allows client_id to be NULL,
# so the field is optional in the JSON.
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


# ---------------------------------------------------------------------
# Non-UUID-keyed
# ---------------------------------------------------------------------

# The schema CHECK fixes which columns each discount_type may carry:
#   volume       client_id optional; country_id / segment_id NULL
#   agency_tier  needs country_code; client_id NULL
#   negotiated   needs client_id (the parent client), segment_code,
#                field_name, reason; leads_min / leads_max NULL
# plan.py builds this payload itself and attaches client_id for
# volume and negotiated rows.
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
    )
}

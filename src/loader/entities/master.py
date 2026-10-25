"""entities/master.py - master DB entity specs."""

from loader.entities import EntitySpec


CLIENTS = EntitySpec(
    name="clients",
    table="clients",
    pk_col="client_id",
    pk_kind="client",
    natural_key=("client_id",),
    columns={
        "client_name":       "client_name",
        "admin_email":       "admin_email",
        "db_connect_string": "db_connect_string",
        "gemini_api_key":    "gemini_api_key",
        "allowed_origins":   "allowed_origins",
        "brand_color":       "brand_color",
        "status":            "status",
        "start_date":        "start_date",
        "end_date":          "end_date",
    },
)

INSTANCES = EntitySpec(
    name="instances",
    table="instances",
    pk_col="instance_id",
    pk_kind="instance",
    natural_key=("instance_key",),
    columns={
        "instance_key":      "instance_id",
        "instance_type":     "instance_type",
        "db_connect_string": "db_connect_string",
        "gemini_api_key":    "gemini_api_key",
        "brand_color":       "brand_color",
    },
)

SETTINGS = EntitySpec(
    name="settings",
    table="settings",
    pk_col="setting_key",
    pk_kind="setting",
    natural_key=("setting_key",),
    columns={
        "setting_key":   "setting_key",
        "setting_value": "setting_value",
        "setting_type":  "setting_type",
        "description":   "description",
        "start_date":    "start_date",
        "end_date":      "end_date",
    },
)

# One subscription row per client (client_id is both PK and FK).
# JSON: client["subscription"] = {tier_id, neon_project_id,
#                                 current_embeddings, subscription_status}
# current_embeddings is a live counter maintained by the platform, so the
# loader only sets it when the row is first created and never resets it.
SUBSCRIPTIONS = EntitySpec(
    name="subscriptions",
    table="client_subscriptions",
    pk_col="client_id",
    pk_kind="subscription",
    natural_key=("client_id",),
    columns={
        "tier_id":             "tier_id",
        "neon_project_id":     "neon_project_id",
        "current_embeddings":  "current_embeddings",
        "subscription_status": "subscription_status",
    },
    insert_only=("current_embeddings",),
)

ALL = {spec.name: spec for spec in (CLIENTS, SUBSCRIPTIONS, INSTANCES, SETTINGS)}

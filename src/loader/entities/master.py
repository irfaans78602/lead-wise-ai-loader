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
        "status":            "status",
        "start_date":        "start_date",
        "end_date":          "end_date",
    },
)

CLIENT_BRANDINGS = EntitySpec(
    name="client_brandings",
    table="client_brandings",
    pk_col="client_id",
    pk_kind="client_branding",
    natural_key=("client_id",),
    columns={
        "display_name":       "display_name",
        "support_email":      "support_email",
        "support_url":        "support_url",
        "primary_color":      "primary_color",
        "primary_contrast":   "primary_contrast",
        "secondary_color":    "secondary_color",
        "accent_color":       "accent_color",
        "bg_color":           "bg_color",
        "surface_color":      "surface_color",
        "text_color":         "text_color",
        "text_muted_color":   "text_muted_color",
        "border_color":       "border_color",
        "radius_px":          "radius_px",
        "font_family":        "font_family",
        "density":            "density",
        "dark_mode":          "dark_mode",
        "logo_light_svg":     "logo_light_svg",
        "logo_dark_svg":      "logo_dark_svg",
        "favicon_svg":        "favicon_svg",
        "logo_light_alt":     "logo_light_alt",
        "logo_dark_alt":      "logo_dark_alt",
        "logo_version":       "logo_version",
        "logo_updated_at":    "logo_updated_at",
    },
)

CLIENT_TEXTS = EntitySpec(
    name="client_texts",
    table="client_texts",
    pk_col="client_text_key",
    pk_kind="client_text",
    natural_key=("client_id", "channel", "locale", "text_key"),
    versioned=True,
    version_key=("start_date",),
    columns={
        "channel":    "channel",
        "locale":     "locale",
        "text_key":   "text_key",
        "text_value": "text_value",
        "start_date": "start_date",
        "end_date":   "end_date",
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

ALL = {spec.name: spec for spec in (CLIENTS, CLIENT_BRANDINGS, CLIENT_TEXTS, SUBSCRIPTIONS, INSTANCES, SETTINGS)}
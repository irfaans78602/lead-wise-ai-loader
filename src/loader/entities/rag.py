"""entities/rag.py - RAG (tenant) DB entity specs."""

from loader.entities import EntitySpec


CLIENTS = EntitySpec(
    name="clients",
    table="clients",
    pk_col="client_id",
    pk_kind="client",
    natural_key=("client_id",),
    columns={
        # Identity
        "display_name":       "display_name",
        "support_email":      "support_email",
        "support_url":        "support_url",
        # Colours
        "primary_color":      "primary_color",
        "primary_contrast":   "primary_contrast",
        "secondary_color":    "secondary_color",
        "accent_color":       "accent_color",
        "bg_color":           "bg_color",
        "surface_color":      "surface_color",
        "text_color":         "text_color",
        "text_muted_color":   "text_muted_color",
        "border_color":       "border_color",
        # Typography
        "radius_px":          "radius_px",
        "font_family":        "font_family",
        "density":            "density",
        "dark_mode":          "dark_mode",
        # Logo
        "logo_light_svg":     "logo_light_svg",
        "logo_dark_svg":      "logo_dark_svg",
        "favicon_svg":        "favicon_svg",
        "logo_light_alt":     "logo_light_alt",
        "logo_dark_alt":      "logo_dark_alt",
        "logo_version":       "logo_version",
        "logo_updated_at":    "logo_updated_at",
        # Policy
        "allowed_origins":    "allowed_origins",
        "scope":              "scope",
        "retention_days":     "retention_days",
        # Status flags - top-level in the JSON client object,
        # not under a subscription sub-object.
        "status":             "status",
        "chat_enabled":       "chat_enabled",
    },
)


# ---------------------------------------------------------------------
# Client texts - per-channel copy
# ---------------------------------------------------------------------
# Composite PK: (client_id, channel, locale, text_key, start_date).
# The loader treats the first four as identity and start_date as the
# version discriminator. write.py and diff.py have dedicated branches
# for this table because the generic _upsert_by_pk helper assumes a
# single-column PK.
#
# The pk_col below is a sentinel ('client_text_key'). It does not
# exist in the database. Its only purpose is to route this spec to
# the composite-key code paths in write.py and diff.py, mirroring
# how pricing_discounts uses 'pricing_discount_id' as its sentinel.
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


ALL = {spec.name: spec for spec in (CLIENTS, CLIENT_TEXTS)}
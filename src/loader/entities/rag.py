"""entities/rag.py - RAG (tenant) DB entity specs."""

from loader.entities import EntitySpec


CLIENTS = EntitySpec(
    name="clients",
    table="clients",
    pk_col="client_id",
    pk_kind="client",
    natural_key=("client_id",),
    columns={
        "status":             "status",
        "chat_enabled":       "chat_enabled",
        "display_name":       "display_name",
        "title":              "title",
        "description":        "description",
        "greeting":           "greeting",
        "placeholder":        "placeholder",
        "disclaimer":         "disclaimer",
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
        "allowed_origins":    "allowed_origins",
        "scope":              "scope",
        "retention_days":     "retention_days",
    },
)

ALL = {spec.name: spec for spec in (CLIENTS,)}
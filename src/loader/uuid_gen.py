"""
uuid_gen.py
Deterministic UUID derivation from natural keys.

Every PK on the loader side is caller-supplied and reproducible. Given
the same natural key, the same UUID is derived. This is what makes
re-running a load idempotent: the second run derives the same PKs, so
it either updates existing rows or is a no-op.

The namespace is fixed. Never change it -- changing it changes every
UUID in every database that was built with this loader.
"""

import uuid


# A fixed, arbitrary UUID. Not derived from anything; chosen once.
# If you ever need to reset (and no production data exists), pick a new
# v4 UUID here and rebuild. Otherwise, leave it alone forever.
NAMESPACE = uuid.UUID("7f3b1a4c-9d2e-4e8a-b1c5-8f6d0e3a7c9b")


def derive(kind: str, *parts) -> uuid.UUID:
    """
    uuid5(NAMESPACE, "<kind>:<part1>:<part2>:...")

    kind is a short entity tag ("client", "ad", "faq", "qscore", ...).
    parts are the natural-key components, coerced to strings.

    Examples:
        derive("client", "leadwise-platform")
        derive("ad", "leadwise-web")
        derive("faq", ad_id_str, "30")
        derive("faq", ad_id_str, "30", "2026-01-15")   # versioned variant
    """
    key = ":".join([kind, *(str(p) for p in parts)])
    return uuid.uuid5(NAMESPACE, key)
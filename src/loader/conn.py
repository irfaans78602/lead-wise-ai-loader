"""
conn.py
Psycopg2 connection helper. Uses RealDictCursor so rows come back
as dicts — the write/diff layers read columns by name.

client_encoding is pinned to utf8. Message text, question text and
option labels carry per-locale strings (ar / fr / es / zh / …); if the
server's default client_encoding were anything other than UTF-8,
Arabic would arrive mangled. Modern PG servers default to UTF-8, so
this is belt-and-braces — a no-op when the server is already correct.

UUID adapter
------------
psycopg2.extras normally registers a uuid.UUID → PG uuid adapter on
import, so callers can pass uuid.UUID objects directly as SQL
parameters. That auto-registration is not reliable on every
interpreter (notably Python 3.14 with psycopg2-binary 2.9.x), so we
call register_uuid() explicitly. It is idempotent — safe to call
regardless of whether extras already did it.
"""

import psycopg2
import psycopg2.extras

# Register the UUID adapter globally, before any connection is made.
psycopg2.extras.register_uuid()


def connect(database_url: str):
    return psycopg2.connect(
        database_url,
        client_encoding="utf8",
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def current_schema_version(conn) -> int | None:
    """Read settings.schema_version, or None if the row is absent."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT setting_value FROM active_settings WHERE setting_key = 'schema_version'"
        )
        row = cur.fetchone()
        return int(row["setting_value"]) if row else None
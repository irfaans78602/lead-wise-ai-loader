"""
conn.py
Psycopg2 connection helper. Uses RealDictCursor so rows come back
as dicts — the write/diff layers read columns by name.
"""

import psycopg2
import psycopg2.extras


def connect(database_url: str):
    return psycopg2.connect(
        database_url,
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
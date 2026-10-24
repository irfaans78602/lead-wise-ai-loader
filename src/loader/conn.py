"""
conn.py
Psycopg2 connection helper. RealDictCursor for name-keyed rows.
client_encoding pinned to utf8.
"""

import psycopg2
import psycopg2.extras

psycopg2.extras.register_uuid()


def connect(database_url: str):
    return psycopg2.connect(
        database_url,
        client_encoding="utf8",
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def current_schema_version(conn) -> int | None:
    with conn.cursor() as cur:
        cur.execute("SELECT to_regclass('public.active_settings') AS t")
        if cur.fetchone()["t"] is None:
            return None
        cur.execute(
            "SELECT setting_value FROM active_settings "
            "WHERE setting_key = 'schema_version'"
        )
        row = cur.fetchone()
        return int(row["setting_value"]) if row else None
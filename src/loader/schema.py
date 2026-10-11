"""
schema.py
Applies SQL from the schema repo. Subcommands: drop, create, seed,
rebuild. All SQL files are read from LW_SCHEMA_ROOT.

Assumes the schema repo layout:
    db/00-drop.sql
    db/10-schema.sql
    db/seeds/*.sql

Each SQL file is a self-contained transaction (BEGIN; ... COMMIT;).
The loader therefore runs them under autocommit — otherwise psycopg2's
implicit transaction collides with the file's BEGIN and raises
ActiveSqlTransaction.
"""

from pathlib import Path

from loader.errors import ConfigError


def _schema_path(schema_root: str, *parts) -> Path:
    p = Path(schema_root).joinpath(*parts)
    if not p.exists():
        raise ConfigError(f"schema file not found: {p}")
    return p


def _run_sql_file(conn, path: Path):
    sql = path.read_text(encoding="utf-8")
    previous = conn.autocommit
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
    finally:
        conn.autocommit = previous


def _seed_files(schema_root: str) -> list[Path]:
    seeds_dir = Path(schema_root) / "db" / "seeds"
    if not seeds_dir.exists():
        raise ConfigError(f"seeds directory not found: {seeds_dir}")
    return sorted(seeds_dir.glob("*.sql"))


def drop(conn, schema_root: str):
    _run_sql_file(conn, _schema_path(schema_root, "db", "00-drop.sql"))


def create(conn, schema_root: str):
    _run_sql_file(conn, _schema_path(schema_root, "db", "10-schema.sql"))


def seed(conn, schema_root: str):
    for path in _seed_files(schema_root):
        _run_sql_file(conn, path)


def rebuild(conn, schema_root: str):
    drop(conn, schema_root)
    create(conn, schema_root)
    seed(conn, schema_root)
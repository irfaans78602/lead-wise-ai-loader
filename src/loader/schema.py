"""
schema.py
Applies SQL from the schema repo. Subcommands: drop, create, seed,
rebuild. All SQL files are read directly from LW_SCHEMA_ROOT.

Layout the loader expects:

    <schema_root>/
        00-*-drop.sql
        10-*-schema.sql
        20-*-seed-base.sql
        30-*-seed-pricing-*.sql
        ...
        _archive/     historical snapshots   — never executed
        _cleanup/     manual clean-up scripts — never executed

Only *.sql files at the schema root are executed. Any subfolder is
invisible to the loader.

Files are bucketed by their two-digit numeric prefix:

    00          drop
    10          schema
    20 .. 89    seeds, applied in ascending filename order

Prefixes 90 and above are not part of the loader's flow. Files that
perform clean-up, ANALYZE, or teardown live outside the execution
path.

Each SQL file is a self-contained transaction (BEGIN; ... COMMIT;).
The loader therefore runs them under autocommit — otherwise psycopg2's
implicit transaction collides with the file's BEGIN and raises
ActiveSqlTransaction.
"""

from pathlib import Path

from loader.errors import ConfigError


def _all_sql_files(schema_root: str) -> list[Path]:
    root = Path(schema_root)
    if not root.exists():
        raise ConfigError(f"schema root not found: {root}")
    files = sorted(p for p in root.glob("*.sql") if p.is_file())
    if not files:
        raise ConfigError(f"no .sql files in {schema_root}")
    return files


def _bucket(files: list[Path]) -> dict[str, list[Path]]:
    """Group files by their two-digit numeric prefix: '00', '10', …"""
    buckets: dict[str, list[Path]] = {}
    for p in files:
        prefix = p.name.split("-", 1)[0]
        if not prefix.isdigit() or len(prefix) != 2:
            continue
        buckets.setdefault(prefix, []).append(p)
    return buckets


def _seed_files(buckets: dict[str, list[Path]]) -> list[Path]:
    """Files with prefix 20 through 89, in ascending order."""
    out: list[Path] = []
    for prefix in sorted(buckets):
        n = int(prefix)
        if 20 <= n <= 89:
            out.extend(buckets[prefix])
    return out


def _require_one(buckets: dict[str, list[Path]], prefix: str,
                 description: str, schema_root: str) -> Path:
    matches = buckets.get(prefix, [])
    if not matches:
        raise ConfigError(
            f"no {prefix}-*.sql ({description}) in {schema_root}"
        )
    if len(matches) > 1:
        raise ConfigError(
            f"multiple {prefix}-*.sql files in {schema_root}: "
            + ", ".join(p.name for p in matches)
        )
    return matches[0]


def _run_sql_file(conn, path: Path):
    sql = path.read_text(encoding="utf-8")
    previous = conn.autocommit
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
    finally:
        conn.autocommit = previous


def drop(conn, schema_root: str):
    buckets = _bucket(_all_sql_files(schema_root))
    _run_sql_file(conn, _require_one(buckets, "00", "drop", schema_root))


def create(conn, schema_root: str):
    buckets = _bucket(_all_sql_files(schema_root))
    _run_sql_file(conn, _require_one(buckets, "10", "schema", schema_root))


def seed(conn, schema_root: str):
    buckets = _bucket(_all_sql_files(schema_root))
    for path in _seed_files(buckets):
        _run_sql_file(conn, path)


def rebuild(conn, schema_root: str):
    drop(conn, schema_root)
    create(conn, schema_root)
    seed(conn, schema_root)
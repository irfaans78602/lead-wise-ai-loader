"""
schema.py
Applies SQL from the schema repo. Subcommands: drop, create, seed,
rebuild. All SQL files are read directly from the profile's schema
root (<PREFIX>_SCHEMA_ROOT, or --schema-root on the command line).

Layout the loader expects:

    <schema_root>/
        00-*-drop.sql
        10-*-schema.sql
        20-*-seed-base.sql
        30-*-seed-pricing-*.sql
        ...
        _archive/     historical snapshots    -- never executed
        _cleanup/     manual clean-up scripts -- never executed

Only *.sql files at the schema root are executed. Any subfolder is
invisible to the loader.

Files are bucketed by their two-digit numeric prefix:

    00          drop
    10          schema
    20 .. 89    seeds, applied in ascending filename order

Prefixes 90 and above are not part of the loader's flow.

Each SQL file is a self-contained transaction (BEGIN; ... COMMIT;).
The loader therefore runs them under autocommit -- otherwise psycopg2's
implicit transaction collides with the file's BEGIN and raises
ActiveSqlTransaction.

Progress is printed to stdout as each file is applied, with a short
elapsed-time marker. The final line is <action>: ok from the CLI.
"""

import sys
import time
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
    """Group files by their two-digit numeric prefix: '00', '10', ..."""
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
    size_kb = path.stat().st_size // 1024
    print(f"  -> {path.name} ({size_kb} KB) ... ", end="", flush=True)
    t0 = time.monotonic()
    sql = path.read_text(encoding="utf-8")
    previous = conn.autocommit
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
    except Exception:
        print("FAILED")
        raise
    finally:
        conn.autocommit = previous
    dt = time.monotonic() - t0
    print(f"ok ({dt:.2f}s)")


def drop(conn, schema_root: str):
    buckets = _bucket(_all_sql_files(schema_root))
    path = _require_one(buckets, "00", "drop", schema_root)
    print("drop:")
    _run_sql_file(conn, path)


def create(conn, schema_root: str):
    buckets = _bucket(_all_sql_files(schema_root))
    path = _require_one(buckets, "10", "schema", schema_root)
    print("create:")
    _run_sql_file(conn, path)


def seed(conn, schema_root: str):
    buckets = _bucket(_all_sql_files(schema_root))
    files = _seed_files(buckets)
    if not files:
        print("seed: (no seed files)")
        return
    print("seed:")
    for path in files:
        _run_sql_file(conn, path)


def rebuild(conn, schema_root: str):
    drop(conn, schema_root)
    create(conn, schema_root)
    seed(conn, schema_root)
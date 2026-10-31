"""
schema.py
Applies SQL from the schema repo.

If commit=False (default), the operations are executed in a transaction
and then rolled back. Pass commit=True to apply the changes.
"""

import re
import sys
import time
from pathlib import Path

from loader.errors import ConfigError


# The schema SQL files carry their own top-level BEGIN;/COMMIT; so they can
# be run standalone in a SQL client. The loader manages the transaction
# itself (dry-run rolls back), so these are stripped before execution --
# otherwise the file's own COMMIT; would commit the schema changes even on
# a dry-run (e.g. `loader db drop` without --commit would really drop).
_TXN_STMT_RE = re.compile(
    r"^\s*(?:BEGIN|COMMIT|ROLLBACK|START\s+TRANSACTION)\s*;\s*$",
    re.IGNORECASE | re.MULTILINE,
)


def _strip_transaction_statements(sql: str) -> str:
    return _TXN_STMT_RE.sub("", sql)


def _all_sql_files(schema_root: str) -> list[Path]:
    root = Path(schema_root)
    if not root.exists():
        raise ConfigError(f"schema root not found: {root}")
    files = sorted(p for p in root.glob("*.sql") if p.is_file())
    if not files:
        raise ConfigError(f"no .sql files in {schema_root}")
    return files


def _bucket(files: list[Path]) -> dict[str, list[Path]]:
    buckets: dict[str, list[Path]] = {}
    for p in files:
        prefix = p.name.split("-", 1)[0]
        if not prefix.isdigit() or len(prefix) != 2:
            continue
        buckets.setdefault(prefix, []).append(p)
    return buckets


def _seed_files(buckets: dict[str, list[Path]]) -> list[Path]:
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
    sql = _strip_transaction_statements(sql)

    try:
        with conn.cursor() as cur:
            cur.execute(sql)
    except Exception:
        print("FAILED")
        raise
    dt = time.monotonic() - t0
    print(f"ok ({dt:.2f}s)")


def _execute_step(conn, path: Path):
    # We do NOT set autocommit here. The caller manages the transaction.
    _run_sql_file(conn, path)


def drop(conn, schema_root: str, commit: bool = False):
    buckets = _bucket(_all_sql_files(schema_root))
    path = _require_one(buckets, "00", "drop", schema_root)
    print("drop:")
    _execute_step(conn, path)
    if not commit:
        print("  (dry-run: rolled back)")
        conn.rollback()
    else:
        conn.commit()


def create(conn, schema_root: str, commit: bool = False):
    buckets = _bucket(_all_sql_files(schema_root))
    path = _require_one(buckets, "10", "schema", schema_root)
    print("create:")
    _execute_step(conn, path)
    if not commit:
        print("  (dry-run: rolled back)")
        conn.rollback()
    else:
        conn.commit()


def seed(conn, schema_root: str, commit: bool = False):
    buckets = _bucket(_all_sql_files(schema_root))
    files = _seed_files(buckets)
    if not files:
        print("seed: (no seed files)")
        return
    print("seed:")
    for path in files:
        _execute_step(conn, path)
    if not commit:
        print("  (dry-run: rolled back)")
        conn.rollback()
    else:
        conn.commit()


def rebuild(conn, schema_root: str, commit: bool = False):
    buckets = _bucket(_all_sql_files(schema_root))

    drop_path = _require_one(buckets, "00", "drop", schema_root)
    create_path = _require_one(buckets, "10", "schema", schema_root)
    seed_paths = _seed_files(buckets)

    print("rebuild:")
    try:
        print("  drop:")
        _execute_step(conn, drop_path)

        print("  create:")
        _execute_step(conn, create_path)

        if seed_paths:
            print("  seed:")
            for path in seed_paths:
                _execute_step(conn, path)

        if not commit:
            print("  (dry-run: rolled back)")
            conn.rollback()
        else:
            conn.commit()
    except Exception as e:
        conn.rollback()
        raise e

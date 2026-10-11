"""
cli.py
Command-line entry point. Two families of subcommand:

    load <input.json> [--commit] [--seed]   load per-client JSON
    db {drop|create|seed|rebuild}           manage the schema

`load` is the default â€” if the first argument isn't `db` or `load`,
it's treated as the input path. So both of these work:

    loader clients/leadwise-ai/60-instance.json
    loader load clients/leadwise-ai/60-instance.json

Without --commit, a load runs in preview mode: the transaction is
opened, writes are performed, state is read back, and the whole thing
is rolled back. Nothing is committed.

--seed flips the default `require` from "existing" to "new". An
explicit "new": true or "new": false in the JSON still wins. Use
--seed for the first load into an empty database.

Exit codes:
    0  clean preview, or successful commit
    1  preflight errors
    2  input file invalid or config error
    3  DB error during the transaction
"""

import argparse
import sys
from pathlib import Path

from loader import __version__
from loader import config as config_mod
from loader import conn as conn_mod
from loader import diff as diff_mod
from loader import preflight as preflight_mod
from loader import schema as schema_mod
from loader import write as write_mod
from loader.errors import (
    ConfigError, FileError, LoaderError, PreflightError,
)
from loader.log import RunLog, file_hash
from loader.plan import load_plan


EXPECTED_SCHEMA_VERSION = 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    # Default subcommand: anything that isn't `db`, `load`, or a flag
    # is treated as the input path for `load`.
    if argv and argv[0] not in ("db", "load", "--help", "-h",
                                "--version", "-V"):
        argv = ["load", *argv]

    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        cfg = config_mod.load(
            data_root=getattr(args, "data_root", None),
            schema_root=getattr(args, "schema_root", None),
        )
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 2

    if args.command == "db":
        return _run_db(cfg, args)

    return _run_load(cfg, args)


# ---------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="loader",
        description="LeadWise AI JSON loader",
    )
    p.add_argument("--version", action="version", version=f"loader {__version__}")

    sub = p.add_subparsers(dest="command", required=True)

    load = sub.add_parser("load", help="load per-client JSON")
    load.add_argument("input", help="path to JSON, relative to data_root")
    load.add_argument("--commit", action="store_true",
                      help="apply the transaction instead of rolling back")
    load.add_argument("--seed", action="store_true",
                      help="default require='new' for entities that don't "
                           "say; use for the first load into an empty DB")
    load.add_argument("--data-root", default=None)
    load.add_argument("--schema-root", default=None)

    db = sub.add_parser("db", help="schema management")
    db.add_argument("action", choices=["drop", "create", "seed", "rebuild"])
    db.add_argument("--data-root", default=None)
    db.add_argument("--schema-root", default=None)

    return p


# ---------------------------------------------------------------------
# db subcommand
# ---------------------------------------------------------------------

def _run_db(cfg, args) -> int:
    conn = conn_mod.connect(cfg.database_url)
    try:
        if args.action == "drop":
            schema_mod.drop(conn, cfg.schema_root)
        elif args.action == "create":
            schema_mod.create(conn, cfg.schema_root)
        elif args.action == "seed":
            schema_mod.seed(conn, cfg.schema_root)
        elif args.action == "rebuild":
            schema_mod.rebuild(conn, cfg.schema_root)
        print(f"db {args.action}: ok")
        return 0
    except LoaderError as e:
        print(f"db {args.action}: {e}", file=sys.stderr)
        return 3
    finally:
        conn.close()


# ---------------------------------------------------------------------
# load subcommand
# ---------------------------------------------------------------------

def _run_load(cfg, args) -> int:
    mode = "commit" if args.commit else "preview"
    default_require = "new" if args.seed else "existing"

    # 1. Read plan
    try:
        plan = load_plan(args.input, cfg.data_root,
                         default_require=default_require)
    except FileError as e:
        print(f"file error: {e}", file=sys.stderr)
        return 2

    # 2. Set up log
    input_path = Path(cfg.data_root) / args.input
    log = RunLog(cfg.data_root, args.input, mode)
    try:
        log.header(
            input_path=args.input,
            database_url=cfg.database_url,
            schema_version=None,   # filled after connect
            expected_schema_version=EXPECTED_SCHEMA_VERSION,
            loader_version=__version__,
            file_sha256=file_hash(str(input_path)),
        )
        if args.seed:
            log.line(f"seed mode: default require = new")
    except OSError as e:
        print(f"log error: {e}", file=sys.stderr)
        log.close()
        return 2

    # 3. Connect
    conn = conn_mod.connect(cfg.database_url)
    try:
        actual_schema_version = conn_mod.current_schema_version(conn)

        # 4. Preflight
        log.section("preflight")
        try:
            preflight_mod.check(conn, plan)
            log.line(f"entities: {len(plan.ops)} checked, all ok")
        except PreflightError as e:
            for msg in e.messages:
                log.line(msg)
            log.footer(result="preflight failed", exit_code=1)
            log.close()
            _print_preflight_errors(e)
            _print_log_path(log.path)
            return 1

        # 5. Snapshot pre-state
        pre = diff_mod.read_state(conn, plan)

        # 6. Transaction
        log.section("transaction")
        log.line("BEGIN")
        try:
            write_mod.execute(conn, plan)
            log.line("writes applied")
            post = diff_mod.read_state(conn, plan)
            log.line("projected state read")
        except Exception as e:
            conn.rollback()
            log.line(f"write error: {e}")
            log.footer(result="write failed", exit_code=3)
            log.close()
            print(f"write error: {e}", file=sys.stderr)
            _print_log_path(log.path)
            return 3

        # 7. Commit or rollback
        if args.commit:
            conn.commit()
            log.line("COMMIT")
            result = "committed"
        else:
            conn.rollback()
            log.line("ROLLBACK")
            result = "preview (rolled back, nothing written)"

        # 8. Diff + summary
        log.changes(pre, post)
        counts = _count_changes(pre, post)
        log.summary(counts)

        # 9. Footer
        log.footer(result=result, exit_code=0)
        log.close()

        _print_summary(counts, mode, log.path, actual_schema_version)
        return 0
    finally:
        conn.close()


# ---------------------------------------------------------------------

def _count_changes(pre: dict, post: dict) -> dict:
    counts = {}
    tables = set(pre) | set(post)

    for table in tables:
        pre_rows = pre.get(table, {})
        post_rows = post.get(table, {})
        inserted = updated = unchanged = 0

        for rid in set(post_rows) - set(pre_rows):
            inserted += 1
        for rid in set(pre_rows) & set(post_rows):
            if _rows_equal(pre_rows[rid], post_rows[rid]):
                unchanged += 1
            else:
                updated += 1

        counts[table] = {
            "inserted": inserted,
            "updated": updated,
            "unchanged": unchanged,
            "extra": None,
        }

    return counts


def _rows_equal(a: dict, b: dict) -> bool:
    for col in set(a) | set(b):
        va, vb = a.get(col), b.get(col)
        if va is None and vb in (None, ""):
            continue
        if vb is None and va in (None, ""):
            continue
        if va != vb:
            return False
    return True


def _print_preflight_errors(e: PreflightError):
    print(f"preflight: {len(e.messages)} error(s)")
    for msg in e.messages:
        print(f"  {msg}")


def _print_summary(counts: dict, mode: str, log_path, schema_version):
    if not counts:
        print("summary:   nothing to do")
    else:
        total = sum(c["inserted"] + c["updated"] for c in counts.values())
        print(f"summary:   {total} changes across {len(counts)} table(s)")
    if schema_version != EXPECTED_SCHEMA_VERSION:
        print(f"warning:   schema_version={schema_version} "
              f"expected={EXPECTED_SCHEMA_VERSION}")
    if mode == "preview":
        print("preview only â€” re-run with --commit to apply")
    else:
        print("committed")
    print(f"log:       {log_path}")


def _print_log_path(log_path):
    print(f"log:       {log_path}")


if __name__ == "__main__":
    raise SystemExit(main())
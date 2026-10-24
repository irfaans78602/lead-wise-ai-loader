"""
cli.py
Command-line entry point. Two families of subcommand:

    load <input.json> [more.json ...] [--commit]
                                            load per-client JSON; several files
                                            run in ONE transaction, in order
    db {drop|create|seed|rebuild}           manage the schema

`load` is the default -- if the first argument isn't `db` or `load`,
it's treated as the input path.

Exit codes:
    0  clean preview, or successful commit
    1  preflight errors
    2  input file invalid, config error, or log-file error
    3  DB error (connect, transaction, or any unexpected failure)
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
from loader import planning as _planning_pkg
from loader.errors import (
    ConfigError, FileError, LoaderError, PreflightError,
)
from loader.log import RunLog, file_hash


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    if argv and argv[0] not in ("db", "load", "--help", "-h",
                                "--version", "-V"):
        argv = ["load", *argv]

    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        cfg = config_mod.load(
            profile=getattr(args, "profile", None),
            data_root=getattr(args, "data_root", None),
            schema_root=getattr(args, "schema_root", None),
        )
        profile = cfg.get(getattr(args, "profile", None))
    except ConfigError as e:
        print(f"config error: {e}", file=sys.stderr)
        return 2

    if args.command == "db":
        return _run_db(profile, args)

    return _run_load(profile, args)


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="loader",
        description="LeadWise AI JSON loader",
    )
    p.add_argument("--version", action="version", version=f"loader {__version__}")

    sub = p.add_subparsers(dest="command", required=True)

    load = sub.add_parser("load", help="load per-client JSON")
    load.add_argument("input", nargs="+",
                      help="path(s) to JSON, relative to data_root; "
                           "several files share one transaction")
    load.add_argument("--commit", action="store_true",
                      help="apply the transaction instead of rolling back")
    load.add_argument("--data-root", default=None)
    load.add_argument("--schema-root", default=None)
    load.add_argument("--profile", default=None)

    db = sub.add_parser("db", help="schema management")
    db.add_argument("action", choices=["drop", "create", "seed", "rebuild"])
    db.add_argument("--data-root", default=None)
    db.add_argument("--schema-root", default=None)
    db.add_argument("--profile", default=None)

    return p


# ---------------------------------------------------------------------
# db subcommand
# ---------------------------------------------------------------------

def _run_db(profile, args) -> int:
    try:
        conn = conn_mod.connect(profile.database_url)
    except Exception as e:
        print(f"database error: could not connect: {e}", file=sys.stderr)
        return 3

    try:
        if args.action == "drop":
            schema_mod.drop(conn, profile.schema_root)
        elif args.action == "create":
            schema_mod.create(conn, profile.schema_root)
        elif args.action == "seed":
            schema_mod.seed(conn, profile.schema_root)
        elif args.action == "rebuild":
            schema_mod.rebuild(conn, profile.schema_root)
        print(f"db {args.action}: ok")
        return 0
    except ConfigError as e:
        print(f"db {args.action}: config error: {e}", file=sys.stderr)
        return 2
    except LoaderError as e:
        print(f"db {args.action}: {e}", file=sys.stderr)
        return 3
    except Exception as e:
        print(f"db {args.action}: {type(e).__name__}: {e}", file=sys.stderr)
        return 3
    finally:
        conn.close()


# ---------------------------------------------------------------------
# load subcommand
# ---------------------------------------------------------------------

def _run_load(profile, args) -> int:
    mode = "commit" if args.commit else "preview"
    inputs = list(args.input)

    # 1. Read plan(s); several files are merged into one plan, in order
    try:
        plan = _planning_pkg.load_many(
            profile.name, inputs, profile.data_root
        )
    except FileError as e:
        print(f"file error: {e}", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"input error: {type(e).__name__}: {e}", file=sys.stderr)
        return 2

    # 2. Connect
    try:
        conn = conn_mod.connect(profile.database_url)
    except Exception as e:
        print(f"database error: could not connect: {e}", file=sys.stderr)
        return 3

    log = None
    try:
        actual_schema_version = conn_mod.current_schema_version(conn)

        # 3. Set up log (after connect so the real schema version is known)
        try:
            log = RunLog(profile.data_root, inputs[0], mode)
            log.header(
                input_path=", ".join(inputs),
                database_url=profile.database_url,
                schema_version=actual_schema_version,
                expected_schema_version=profile.expected_schema_version,
                loader_version=__version__,
                file_sha256=_hashes(profile.data_root, inputs),
            )
        except OSError as e:
            print(f"log error: {e}", file=sys.stderr)
            return 2

        return _run_load_body(
            conn, plan, args, profile, log, mode, actual_schema_version
        )

    except Exception as e:
        # Anything not handled below: roll back, record it, exit 3.
        try:
            conn.rollback()
        except Exception:
            pass
        print(f"unexpected error: {type(e).__name__}: {e}", file=sys.stderr)
        if log is not None:
            log.line(f"unexpected error: {type(e).__name__}: {e}")
            log.footer(result="unexpected error", exit_code=3)
            _print_log_path(log.path)
        return 3
    finally:
        if log is not None:
            log.close()
        conn.close()


def _hashes(data_root: str, inputs: list) -> str:
    """One hash for a single file; 'name=hash; name=hash' for several."""
    if len(inputs) == 1:
        return file_hash(str(Path(data_root) / inputs[0]))
    return "; ".join(
        f"{name}={file_hash(str(Path(data_root) / name))}" for name in inputs
    )


def _run_load_body(conn, plan, args, profile, log, mode,
                   actual_schema_version) -> int:
    # 4. Preflight
    print("preflight", flush=True)
    log.section("preflight")
    try:
        preflight_mod.check(conn, plan)
        print(f"  entities: {len(plan.ops)} checked, all ok", flush=True)
        log.line(f"entities: {len(plan.ops)} checked, all ok")
    except PreflightError as e:
        for msg in e.messages:
            log.line(msg)
        log.footer(result="preflight failed", exit_code=1)
        _print_preflight_errors(e)
        _print_log_path(log.path)
        return 1

    # 5. Snapshot pre-state
    pre = diff_mod.read_state(conn, plan)

    # 6. Transaction
    print("transaction", flush=True)
    log.section("transaction")
    log.line("BEGIN")
    try:
        write_mod.execute(conn, plan)
        print("  writes applied", flush=True)
        log.line("writes applied")
        post = diff_mod.read_state(conn, plan)
        print("  projected state read", flush=True)
        log.line("projected state read")
    except Exception as e:
        conn.rollback()
        log.line(f"write error: {e}")
        log.footer(result="write failed", exit_code=3)
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

    _print_summary(counts, mode, log.path, actual_schema_version,
                   profile.expected_schema_version)
    return 0


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


def _print_summary(counts: dict, mode: str, log_path,
                   actual_schema_version, expected_schema_version):
    if not counts:
        print("summary:   nothing to do")
    else:
        total = sum(c["inserted"] + c["updated"] for c in counts.values())
        print(f"summary:   {total} changes across {len(counts)} table(s)")
    if (expected_schema_version is not None
            and actual_schema_version != expected_schema_version):
        print(f"warning:   schema_version={actual_schema_version} "
              f"expected={expected_schema_version}")
    if mode == "preview":
        print("preview only -- re-run with --commit to apply")
    else:
        print("committed")
    print(f"log:       {log_path}")


def _print_log_path(log_path):
    print(f"log:       {log_path}")


if __name__ == "__main__":
    raise SystemExit(main())

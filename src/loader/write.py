"""
write.py
Executes a Plan's ops inside a transaction. The caller controls the
final verb: preview calls ROLLBACK, commit calls COMMIT.

All writes go through a single `execute` function so preview and
commit are guaranteed to run the same code path.

Progress output
---------------
Ops are grouped by spec.table and executed group by group. Each group
prints a header before its first op and a per-table count on
completion. Every op prints a single line showing its logical key and
— where meaningful — a short entity-specific hint (question_id and
type for FAQs, level_code and score range for score bands, etc.).

Failures print the table name and the failing op's logical key so it's
obvious which component broke.

Versioned tables (faqs, ad_confirmations, ad_reopen_prompts,
qualification_score, client_messages) carry a two-step update:

  1. If a *different* current version of the same logical key exists,
     close it by setting its end_date. The close date comes from
     op.closes_previous if the JSON supplied it, otherwise it's
     inferred as (start_date - 1 day).

  2. Upsert the new version by its PK. Re-runs are idempotent: the
     first run closes the old and inserts the new; the second run
     finds nothing to close and updates the row in place.

JSONB serialisation
-------------------
Nested dicts and lists (message_text, question_text, options, …) are
serialised with ensure_ascii=False so non-ASCII text lands in the DB
as real UTF-8 rather than \\uXXXX escapes. Both forms are valid JSON
and both round-trip through json.loads, but the human-readable form is
what shows up in a SQL client. PG stores either form identically.
"""

import json
import sys
from collections import OrderedDict
from datetime import date, timedelta

from loader.plan import Plan, PlanOp


def execute(conn, plan: Plan):
    """
    Execute every op in plan.ops, grouped by spec.table in plan order.

    Groups are formed by first-seen order of spec.table across the
    plan, which is deterministic: plan.py walks the JSON in a fixed
    order (clients → client_users → root_ad → ad_matrix → pricing),
    and each entity type maps to one table.
    """
    groups: "OrderedDict[str, list[PlanOp]]" = OrderedDict()
    for op in plan.ops:
        groups.setdefault(op.spec.table, []).append(op)

    for table, ops in groups.items():
        print(f"  writing {table} ({len(ops)})...", flush=True)
        done = 0
        for op in ops:
            _print_op(op, table)
            try:
                _write_one(conn, op)
            except Exception as e:
                print(
                    f"    {table}: FAILED on {_fmt_op(op)}: {e}",
                    file=sys.stderr, flush=True,
                )
                raise
            done += 1
        print(f"    {table}: {done} ok", flush=True)


def _print_op(op: PlanOp, table: str):
    """One line per op: logical key + entity-specific hint."""
    key = ":".join(str(k) for k in op.logical_key)
    hint = _hint(op)
    pad = " " * (len(table) + 6)
    if hint:
        print(f"    {table}[{key}]{pad}{hint}", flush=True)
    else:
        print(f"    {table}[{key}]", flush=True)


def _hint(op: PlanOp) -> str:
    """
    Short human-readable suffix describing the row. Empty for tables
    where the logical key already tells the whole story.
    """
    table = op.spec.table
    p = op.payload

    if table == "ads":
        # Root vs leaf, plus the language for leaves.
        if p.get("reuse_ad_id") is None:
            return "(root)"
        lang = p.get("language_id") or ""
        return f"leaf lang={lang}" if lang else "leaf"

    if table == "faqs":
        qid = p.get("question_id")
        qorder = p.get("question_order")
        qtype = p.get("question_type", "")
        return f"question_id={qid} order={qorder} {qtype}".rstrip()

    if table == "qualification_score":
        level = p.get("level_code", "")
        score = p.get("score", "")
        return f"level={level} score={score}"

    if table == "pricing_discounts":
        pct = p.get("discount_pct", "")
        label = p.get("label", "")
        return f"pct={pct} label={label}"

    if table == "client_messages":
        return "message_text"

    if table == "ad_confirmations":
        return "message_text"

    if table == "ad_reopen_prompts":
        return "prompt_text + buttons"

    if table == "client_whatsapps":
        return p.get("display_phone_number", "")

    if table == "clients":
        return p.get("name", "")

    if table == "client_users":
        return p.get("email", "")

    return ""


def _fmt_op(op: PlanOp) -> str:
    """Human-readable identifier for error messages."""
    key = ":".join(str(k) for k in op.logical_key)
    return f"{op.spec.table}[{key}]"


def _write_one(conn, op: PlanOp):
    spec = op.spec
    if spec.pk_col == "pricing_discount_id":
        _upsert_pricing_discount(conn, op)
    elif spec.versioned:
        _write_versioned(conn, op)
    else:
        _upsert_by_pk(conn, op)


def _write_versioned(conn, op: PlanOp):
    """
    Close any other current version of the same logical key, then
    upsert this version.
    """
    spec = op.spec

    where = " AND ".join(f"{col} = %s" for col in spec.natural_key)
    params = [op.payload[col] for col in spec.natural_key]

    # Find any current version with a different PK (i.e. different
    # start_date). If none, this is either a first insert or an in-place
    # edit of the current version — no close needed.
    with conn.cursor() as cur:
        cur.execute(
            f"""SELECT {spec.pk_col} FROM {spec.table}
                WHERE {where}
                  AND end_date = '9999-12-31'
                  AND {spec.pk_col} <> %s""",
            [*params, op.pk],
        )
        old_rows = cur.fetchall()

    if old_rows:
        close_date = op.closes_previous
        if close_date is None:
            close_date = _infer_close_date(op.payload["start_date"])
        with conn.cursor() as cur:
            cur.execute(
                f"""UPDATE {spec.table}
                    SET end_date = %s
                    WHERE {where}
                      AND end_date = '9999-12-31'
                      AND {spec.pk_col} <> %s""",
                [close_date, *params, op.pk],
            )

    _upsert_by_pk(conn, op)


def _infer_close_date(start_date) -> str:
    """start_date - 1 day, as an ISO string. Accepts a date, a
    datetime, or an ISO string. Returns an ISO date string."""
    if isinstance(start_date, str):
        d = date.fromisoformat(start_date[:10])
    elif isinstance(start_date, date):
        d = start_date
    else:
        # Fallback: assume it's already something date-like
        return str(start_date)
    return (d - timedelta(days=1)).isoformat()


def _upsert_by_pk(conn, op: PlanOp):
    spec = op.spec
    cols = list(op.payload.keys())
    placeholders = ", ".join(["%s"] * len(cols))
    values = [_serialize(op.payload[c]) for c in cols]

    update_cols = [c for c in cols if c != spec.pk_col]
    update_clause = ", ".join(f"{c} = EXCLUDED.{c}" for c in update_cols)
    if not update_clause:
        update_clause = f"{spec.pk_col} = EXCLUDED.{spec.pk_col}"

    sql = (
        f"INSERT INTO {spec.table} ({', '.join(cols)}) "
        f"VALUES ({placeholders}) "
        f"ON CONFLICT ({spec.pk_col}) DO UPDATE SET {update_clause}"
    )
    with conn.cursor() as cur:
        cur.execute(sql, values)


def _upsert_pricing_discount(conn, op: PlanOp):
    """
    Partial unique index in the schema:
      UNIQUE (discount_type, leads_min, leads_max, start_date)
      WHERE client_id IS NULL AND country_id IS NULL AND segment_id IS NULL

    ON CONFLICT must match the predicate. The loader only ever writes
    platform-wide volume tiers, so the predicate is exactly the one
    above.
    """
    p = op.payload
    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO pricing_discounts
                   (discount_type, leads_min, leads_max, discount_pct,
                    label, reason, start_date, end_date)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
               ON CONFLICT (discount_type, leads_min, leads_max, start_date)
                   WHERE (client_id IS NULL AND country_id IS NULL AND segment_id IS NULL)
               DO UPDATE SET
                   discount_pct = EXCLUDED.discount_pct,
                   label        = EXCLUDED.label,
                   reason       = EXCLUDED.reason,
                   end_date     = EXCLUDED.end_date""",
            (
                p["discount_type"], p["leads_min"], p["leads_max"],
                p["discount_pct"], p["label"], p.get("reason"),
                p["start_date"], p["end_date"],
            ),
        )


def _serialize(v):
    if isinstance(v, (dict, list)):
        return json.dumps(v, ensure_ascii=False)
    return v
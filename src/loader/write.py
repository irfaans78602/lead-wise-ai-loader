"""
write.py
Executes a Plan's ops inside a transaction. The caller controls the
final verb: preview calls ROLLBACK, commit calls COMMIT.

All writes go through a single `execute` function so preview and
commit are guaranteed to run the same code path.

Write semantics
---------------
Every op is "update if the key exists, else insert":

  - Tables keyed by a PK (UUID, or google_sub for client_users) use
    INSERT ... ON CONFLICT (pk) DO UPDATE, which is atomic. The
    `xmax = 0` trick in RETURNING tells us whether the row was
    inserted or updated.
  - pricing_discounts is keyed by (client_id, country_id, segment_id,
    field_name, discount_type, leads_min, leads_max, start_date),
    with NULL-safe comparison.

Versioned tables (faqs, ad_confirmations, ad_reopen_prompts,
qualification_score, client_messages) are plain upserts. Older
versions are never closed; each version is an independent row keyed
by its derived UUID.

Progress output
---------------
Ops are grouped by spec.table and executed group by group. Each op
prints a single line with its action (INSERT / UPDATE), logical key
and a short entity-specific hint.

JSONB serialisation
-------------------
Nested dicts and lists (message_text, question_text, options, ...) are
serialised with ensure_ascii=False so non-ASCII text lands in the DB
as real UTF-8 rather than \\uXXXX escapes.
"""

import json
import sys
from collections import OrderedDict

from loader.plan import Plan, PlanOp


def execute(conn, plan: Plan):
    """
    Execute every op in plan.ops, grouped by spec.table in plan order.
    """
    groups: "OrderedDict[str, list[PlanOp]]" = OrderedDict()
    for op in plan.ops:
        groups.setdefault(op.spec.table, []).append(op)

    for table, ops in groups.items():
        print(f"  writing {table} ({len(ops)})...", flush=True)
        done = 0
        for op in ops:
            try:
                action = _write_one(conn, op)
            except Exception as e:
                print(
                    f"    {table}: FAILED on {_fmt_op(op)}: {e}",
                    file=sys.stderr, flush=True,
                )
                raise
            _print_op(op, table, action)
            done += 1
        print(f"    {table}: {done} ok", flush=True)


def _print_op(op: PlanOp, table: str, action: str = ""):
    """One line per op: action + logical key + entity-specific hint."""
    key = ":".join(str(k) for k in op.logical_key)
    hint = _hint(op)
    pad = " " * (len(table) + 6)
    tag = f"{action.upper():<7} " if action else ""
    line = f"    {tag}{table}[{key}]"
    print(f"{line}{pad}{hint}" if hint else line, flush=True)


def _hint(op: PlanOp) -> str:
    """
    Short human-readable suffix describing the row. Empty for tables
    where the logical key already tells the whole story.
    """
    table = op.spec.table
    p = op.payload

    if table == "ads":
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

    if table == "clients":
        return p.get("name", "")

    if table == "client_users":
        return p.get("email", "")

    return ""


def _fmt_op(op: PlanOp) -> str:
    """Human-readable identifier for error messages."""
    key = ":".join(str(k) for k in op.logical_key)
    return f"{op.spec.table}[{key}]"


def _write_one(conn, op: PlanOp) -> str:
    spec = op.spec
    if spec.pk_col == "pricing_discount_id":
        return _upsert_pricing_discount(conn, op)
    if spec.versioned:
        return _write_versioned(conn, op)
    return _upsert_by_pk(conn, op)


def _write_versioned(conn, op: PlanOp) -> str:
    # Versions are independent rows keyed by their derived UUID.
    # Nothing is closed; older versions keep their end_date.
    return _upsert_by_pk(conn, op)


def _upsert_by_pk(conn, op: PlanOp) -> str:
    """Atomic update-else-insert on the PK. Returns "insert" or "update"."""
    spec = op.spec
    cols = list(op.payload.keys())
    values = [_serialize(op.payload[c]) for c in cols]

    update_cols = [c for c in cols if c != spec.pk_col]
    update_clause = ", ".join(f"{c} = EXCLUDED.{c}" for c in update_cols) \
        or f"{spec.pk_col} = EXCLUDED.{spec.pk_col}"

    sql = (
        f"INSERT INTO {spec.table} ({', '.join(cols)}) "
        f"VALUES ({', '.join(['%s'] * len(cols))}) "
        f"ON CONFLICT ({spec.pk_col}) DO UPDATE SET {update_clause} "
        f"RETURNING (xmax = 0) AS inserted"
    )
    with conn.cursor() as cur:
        cur.execute(sql, values)
        return "insert" if cur.fetchone()["inserted"] else "update"


def _upsert_pricing_discount(conn, op: PlanOp) -> str:
    """Update if the row exists, else insert. A row is identified by
    (client_id, country_id, segment_id, field_name, type, min, max,
    start_date), compared NULL-safely. client_id is set for volume
    and negotiated discounts; agency_tier rows leave it NULL."""
    p = op.payload
    key_cols = ["client_id", "country_id", "segment_id", "field_name",
                "discount_type", "leads_min", "leads_max", "start_date"]
    key_vals = [p.get(c) for c in key_cols]
    where = " AND ".join(f"{c} IS NOT DISTINCT FROM %s" for c in key_cols)

    with conn.cursor() as cur:
        cur.execute(f"SELECT 1 FROM pricing_discounts WHERE {where}", key_vals)
        if cur.fetchone():
            set_cols = [c for c in p if c not in key_cols]
            if set_cols:
                cur.execute(
                    f"UPDATE pricing_discounts "
                    f"SET {', '.join(f'{c} = %s' for c in set_cols)} "
                    f"WHERE {where}",
                    [*(_serialize(p[c]) for c in set_cols), *key_vals],
                )
            return "update"

        cols = list(p)
        cur.execute(
            f"INSERT INTO pricing_discounts ({', '.join(cols)}) "
            f"VALUES ({', '.join(['%s'] * len(cols))})",
            [_serialize(p[c]) for c in cols],
        )
        return "insert"


def _serialize(v):
    if isinstance(v, (dict, list)):
        return json.dumps(v, ensure_ascii=False)
    return v

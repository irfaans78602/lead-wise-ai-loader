"""
write.py
Executes a Plan's ops inside a transaction.
"""

import json
import sys
from collections import OrderedDict

from loader.planning.website import Plan, PlanOp


def execute(conn, plan: Plan):
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
    key = ":".join(str(k) for k in op.logical_key)
    hint = _hint(op)
    pad = " " * (len(table) + 6)
    tag = f"{action.upper():<7} " if action else ""
    line = f"    {tag}{table}[{key}]"
    print(f"{line}{pad}{hint}" if hint else line, flush=True)


def _hint(op: PlanOp) -> str:
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
        # website: name, master: client_name, rag: display_name
        return (p.get("name") or p.get("client_name")
                or p.get("display_name") or "")
    if table == "client_users":
        return p.get("email", "")
    if table == "instances":
        return p.get("instance_type", "")
    if table == "client_subscriptions":
        return (f"tier={p.get('tier_id', '')} "
                f"status={p.get('subscription_status', '')}").rstrip()
    if table == "settings":
        return p.get("setting_type", "") or ""
    return ""


def _fmt_op(op: PlanOp) -> str:
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
    return _upsert_by_pk(conn, op)


def _upsert_by_pk(conn, op: PlanOp) -> str:
    spec = op.spec
    cols = list(op.payload.keys())
    values = [_serialize(op.payload[c]) for c in cols]

    update_cols = [c for c in cols
                   if c != spec.pk_col and c not in spec.insert_only]
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

"""
write.py
Executes a Plan's ops inside a transaction. The caller controls the
final verb: preview calls ROLLBACK, commit calls COMMIT.

All writes go through a single `execute` function so preview and
commit are guaranteed to run the same code path.
"""

import json
from loader.plan import Plan, PlanOp


def execute(conn, plan: Plan):
    for op in plan.ops:
        _write_one(conn, op)


def _write_one(conn, op: PlanOp):
    if op.spec.pk_col == "pricing_discount_id":
        _upsert_pricing_discount(conn, op)
    else:
        _upsert_by_pk(conn, op)


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
        return json.dumps(v)
    return v
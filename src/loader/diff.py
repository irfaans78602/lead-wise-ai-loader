"""
diff.py
Reads the current state of every row referenced by a Plan.

Called twice per run:
  - before write.execute(), to snapshot the pre-state
  - after write.execute(), to read the projected post-state

The two snapshots drive the insert/update/unchanged counts and the
per-column before->after diff in the log. Same implementation, two
call sites.
"""

from loader.planning.website import Plan, PlanOp


def read_state(conn, plan: Plan) -> dict:
    """
    Returns {table_name: {pk_repr: row_dict}} for every row the plan
    references. Rows that don't exist yet are absent.
    """
    result: dict[str, dict] = {}

    for op in plan.ops:
        row = _fetch_one(conn, op)
        if row is not None:
            key = _row_identity(op, row)
            result.setdefault(op.spec.table, {})[key] = dict(row)

    return result


def _row_identity(op: PlanOp, row: dict):
    """
    A stable string key per row for cross-snapshot matching.

    Most tables: the PK.
    pricing_discounts: all identifying columns (see write.py).
    """
    spec = op.spec
    if spec.pk_col == "pricing_discount_id":
        p = row
        return (f"{p.get('client_id')}:{p.get('country_id')}:"
                f"{p.get('segment_id')}:{p.get('field_name')}:"
                f"{p['discount_type']}:{p['leads_min']}:{p['leads_max']}:"
                f"{p['start_date']}")
    return str(row[spec.pk_col])


def _fetch_one(conn, op: PlanOp):
    spec = op.spec

    if spec.pk_col == "pricing_discount_id":
        p = op.payload
        with conn.cursor() as cur:
            cur.execute(
                """SELECT * FROM pricing_discounts
                   WHERE client_id IS NOT DISTINCT FROM %s
                     AND country_id IS NOT DISTINCT FROM %s
                     AND segment_id IS NOT DISTINCT FROM %s
                     AND field_name IS NOT DISTINCT FROM %s
                     AND discount_type = %s
                     AND leads_min IS NOT DISTINCT FROM %s
                     AND leads_max IS NOT DISTINCT FROM %s
                     AND start_date = %s""",
                (p.get("client_id"), p.get("country_id"),
                 p.get("segment_id"), p.get("field_name"),
                 p["discount_type"], p["leads_min"], p["leads_max"],
                 p["start_date"]),
            )
            return cur.fetchone()

    with conn.cursor() as cur:
        cur.execute(
            f"SELECT * FROM {spec.table} WHERE {spec.pk_col} = %s",
            (op.pk,),
        )
        return cur.fetchone()
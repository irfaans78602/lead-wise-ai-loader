"""
preflight.py
Runs before the transaction opens. Every check that can be done
without writing is done here.

Checks:
  1. For every PlanOp with require="existing", the row exists.
  2. For every PlanOp with require="new", the row does NOT exist.
  3. Natural-key columns that carry a code string (country_id holding
     "ZA" instead of 5) are resolved to the referenced table's ID.

If any check fails, PreflightError is raised with all failures. The
loader prints them and exits non-zero without writing anything.
"""

from loader.errors import PreflightError
from loader.plan import Plan, PlanOp


# PG columns whose payload value may arrive as a natural-key string and
# must be resolved to the referenced table's PK.
_LOOKUPS = {
    "country_id":  ("countries",  "country_id",  "code"),
    "segment_id":  ("segments",   "segment_id",  "code"),
    "currency_id": ("currencies", "currency_id", "code"),
    "language_id": ("languages",  "language_id", "code"),
}


def check(conn, plan: Plan) -> None:
    errors = []

    for op in plan.ops:
        _resolve_lookups(conn, op, errors)
        _check_require(conn, op, errors)

    if errors:
        raise PreflightError(errors)


def _resolve_lookups(conn, op: PlanOp, errors: list):
    """
    Turn code strings into IDs. Runs before _check_require so that
    existence checks see fully-resolved payloads. Idempotent: values
    that are already non-strings are skipped, so re-running on the
    same op is safe.
    """
    for pg_col, value in list(op.payload.items()):
        spec = _LOOKUPS.get(pg_col)
        if spec is None:
            continue
        if not isinstance(value, str):
            continue

        table, id_col, code_col = spec
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT {id_col} AS id FROM {table} WHERE {code_col} = %s",
                (value,),
            )
            row = cur.fetchone()
        if row is None:
            errors.append(
                f"{op.spec.table}: {pg_col}='{value}' not found in {table}"
            )
        else:
            op.payload[pg_col] = row["id"]


def _check_require(conn, op: PlanOp, errors: list):
    spec = op.spec
    exists = _row_exists(conn, op)

    if op.require == "existing" and not exists:
        errors.append(
            f"{spec.table}: {_fmt_key(op.logical_key)} required existing but "
            f"not found ({op.source_path})"
        )
    elif op.require == "new" and exists:
        errors.append(
            f"{spec.table}: {_fmt_key(op.logical_key)} required new but "
            f"already exists ({op.source_path})"
        )


def _row_exists(conn, op: PlanOp) -> bool:
    """
    Unversioned: PK exists.
    Versioned:   a current version exists for the logical key, OR the
                 exact (logical key, start_date) row exists.
    """
    spec = op.spec

    if not spec.versioned:
        if spec.pk_col == "pricing_discount_id":
            return _pricing_discount_exists(conn, op)
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT 1 FROM {spec.table} WHERE {spec.pk_col} = %s",
                (op.pk,),
            )
            return cur.fetchone() is not None

    # Versioned.
    # 1. Does the exact (logical_key, start_date) row exist?
    where = " AND ".join(f"{col} = %s" for col in spec.natural_key)
    params = [op.payload[col] for col in spec.natural_key]
    exact_where = where + " AND start_date = %s"
    exact_params = params + [op.payload["start_date"]]

    with conn.cursor() as cur:
        cur.execute(
            f"SELECT 1 FROM {spec.table} WHERE {exact_where}",
            exact_params,
        )
        if cur.fetchone() is not None:
            return True

    # 2. Is there a current version for the logical key?
    cur_where = where + " AND end_date = '9999-12-31'"
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT 1 FROM {spec.table} WHERE {cur_where}",
            params,
        )
        return cur.fetchone() is not None


def _pricing_discount_exists(conn, op: PlanOp) -> bool:
    p = op.payload
    with conn.cursor() as cur:
        cur.execute(
            """SELECT 1 FROM pricing_discounts
               WHERE discount_type = %s
                 AND leads_min IS NOT DISTINCT FROM %s
                 AND leads_max IS NOT DISTINCT FROM %s
                 AND end_date = '9999-12-31'""",
            (p["discount_type"], p.get("leads_min"), p.get("leads_max")),
        )
        return cur.fetchone() is not None


def _fmt_key(key: tuple) -> str:
    return ":".join(str(k) for k in key)
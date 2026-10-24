"""
preflight.py
Runs before the transaction opens. Every check that can be done
without writing is done here.
"""

import uuid

from loader import uuid_gen
from loader.errors import PreflightError
from loader.planning.website import Plan, PlanOp


_LOOKUPS = {
    "country_id":  ("countries",  "country_id",  "code"),
    "segment_id":  ("segments",   "segment_id",  "code"),
    "currency_id": ("currencies", "currency_id", "code"),
    "language_id": ("languages",  "language_id", "code"),
}


def check(conn, plan: Plan) -> None:
    errors = []

    for op in plan.ops:
        _resolve_client_key(op)
        _resolve_lookups(conn, op, errors)

    if errors:
        raise PreflightError(errors)


def _resolve_client_key(op: PlanOp):
    v = op.payload.get("client_id")
    if isinstance(v, str):
        try:
            op.payload["client_id"] = uuid.UUID(v)
        except ValueError:
            op.payload["client_id"] = uuid_gen.derive("client", v)


def _resolve_lookups(conn, op: PlanOp, errors: list):
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
"""
preflight.py
Runs before the transaction opens. Every check that can be done
without writing is done here.

Checks / resolutions:
  1. client_id values that arrive as a client_key string
     ("leadwise-platform") are converted to the client's UUID, derived
     the same way clients.client_id is derived.
  2. Code-string columns (country_id holding "ZA" instead of 5) are
     resolved to the referenced table's ID.

Row existence is NOT checked: write.py updates a row if its key exists
and inserts it otherwise.

If any check fails, PreflightError is raised with all failures. The
loader prints them and exits non-zero without writing anything.
"""

import uuid

from loader import uuid_gen
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
        _resolve_client_key(op)
        _resolve_lookups(conn, op, errors)

    if errors:
        raise PreflightError(errors)


def _resolve_client_key(op: PlanOp):
    """
    client_users / pricing_discounts map JSON `client_key` to the
    `client_id` column. The value arrives as a string; turn it into the
    client's UUID. A string that is already a UUID is parsed as-is,
    anything else is derived with uuid_gen.derive("client", key).
    No-op when the value is absent or already a UUID.
    """
    v = op.payload.get("client_id")
    if isinstance(v, str):
        try:
            op.payload["client_id"] = uuid.UUID(v)
        except ValueError:
            op.payload["client_id"] = uuid_gen.derive("client", v)


def _resolve_lookups(conn, op: PlanOp, errors: list):
    """
    Turn code strings into IDs. Idempotent: values that are already
    non-strings are skipped, so re-running on the same op is safe.
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

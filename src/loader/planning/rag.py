"""planning/rag.py - plan builder for the RAG (tenant) DB."""

from loader.entities import rag as E
from loader.planning.website import (
    Plan, PlanOp, read_json, require, resolve_client_id,
)


def load_plan(json_path: str, data_root: str) -> Plan:
    payload = read_json(json_path, data_root)
    plan = Plan()

    # 10-client.json can be a bare object or an array (for symmetry with master).
    if isinstance(payload, list):
        clients = payload
    elif isinstance(payload, dict) and "client_key" in payload:
        clients = [payload]
    else:
        clients = payload.get("clients", [])

    for c in clients:
        client_key = require(c, "client_key", "clients")
        cid = resolve_client_id(c, f"clients[{client_key}]")

        row = {"client_id": cid}
        for json_field, pg_col in E.CLIENTS.columns.items():
            if json_field in c:
                row[pg_col] = c[json_field]
        plan.add(PlanOp(
            spec=E.CLIENTS,
            pk=cid,
            payload=row,
            logical_key=(client_key,),
            source_path=json_path,
        ))

    return plan
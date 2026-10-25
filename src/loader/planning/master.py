"""planning/master.py - plan builder for the master DB."""

import uuid

from loader.entities import master as E
from loader.planning.website import (
    Plan, PlanOp, read_json, require, resolve_client_id,
)
from loader.errors import FileError
from loader.uuid_gen import derive


def load_plan(json_path: str, data_root: str) -> Plan:
    payload = read_json(json_path, data_root)
    plan = Plan()

    # Two shapes are accepted:
    #   client.json   -> a JSON array of clients
    #   20-settings.json -> {"settings": [...]}
    if isinstance(payload, list):
        clients = payload
        settings = []
    else:
        clients = payload.get("clients", [])
        settings = payload.get("settings", [])

    for client in clients:
        client_key = require(client, "client_key", "clients")
        client_id = resolve_client_id(client, f"clients[{client_key}]")

        row = {"client_id": client_id}
        for json_field, pg_col in E.CLIENTS.columns.items():
            if json_field in client:
                row[pg_col] = client[json_field]
        plan.add(PlanOp(
            spec=E.CLIENTS,
            pk=client_id,
            payload=row,
            logical_key=(client_key,),
            source_path=json_path,
        ))

        subscription = client.get("subscription")
        if subscription:
            _plan_subscription(client_id, client_key, subscription,
                               plan, json_path)

        for inst in client.get("instances", []):
            _plan_instance(client_id, client_key, inst, plan, json_path)

    for s in settings:
        _plan_setting(s, plan, json_path)

    return plan


def _plan_subscription(client_id, client_key, sub, plan, source):
    where = f"clients[{client_key}].subscription"
    if not isinstance(sub, dict):
        raise FileError(f"{where}: must be an object")
    require(sub, "tier_id", where)

    embeddings = sub.get("current_embeddings")
    if embeddings is not None:
        if isinstance(embeddings, bool) or not isinstance(embeddings, int) \
                or embeddings < 0:
            raise FileError(
                f"{where}: current_embeddings must be a whole number "
                f">= 0, got {embeddings!r}"
            )

    row = {"client_id": client_id}
    for json_field, pg_col in E.SUBSCRIPTIONS.columns.items():
        if json_field in sub:
            row[pg_col] = sub[json_field]
    plan.add(PlanOp(
        spec=E.SUBSCRIPTIONS,
        pk=client_id,
        payload=row,
        logical_key=(client_key, "subscription"),
        source_path=source,
    ))


def _plan_instance(client_id, client_key, inst, plan, source):
    where = f"clients[{client_key}].instances"
    ikey = require(inst, "instance_key", where)

    if inst.get("instance_id"):
        try:
            instance_id = uuid.UUID(str(inst["instance_id"]))
        except ValueError as e:
            raise FileError(
                f"{where}[{ikey}]: instance_id {inst['instance_id']!r} "
                f"is not a valid UUID"
            ) from e
    else:
        instance_id = derive("instance", ikey)

    row = {
        "instance_id":   instance_id,
        "client_id":     client_id,
        "instance_type": require(inst, "instance_type", f"{where}[{ikey}]"),
    }
    for opt in ("db_connect_string", "gemini_api_key", "brand_color"):
        if opt in inst:
            row[opt] = inst[opt]
    plan.add(PlanOp(
        spec=E.INSTANCES,
        pk=instance_id,
        payload=row,
        logical_key=(ikey,),
        source_path=source,
    ))


def _plan_setting(s: dict, plan: Plan, source: str):
    key = require(s, "setting_key", "settings")
    row = {"setting_key": key}
    for json_field, pg_col in E.SETTINGS.columns.items():
        if json_field in s:
            row[pg_col] = s[json_field]
    plan.add(PlanOp(
        spec=E.SETTINGS,
        pk=key,
        payload=row,
        logical_key=(key,),
        source_path=source,
    ))

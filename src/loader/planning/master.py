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

        # 1. Clients row (routing & identity)
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

        # 2. Branding row
        branding = client.get("branding")
        if branding:
            _plan_branding(client_id, client_key, branding, plan, json_path)

        # 3. Client texts
        texts = client.get("texts", [])
        if not isinstance(texts, list):
            raise FileError(
                f"clients[{client_key}].texts: must be a list, "
                f"got {type(texts).__name__}"
            )
        _plan_client_texts(client_id, client_key, texts, plan, json_path)

        # 4. Subscription
        subscription = client.get("subscription")
        if subscription:
            _plan_subscription(client_id, client_key, subscription, plan, json_path)

        # 5. Instances
        for inst in client.get("instances", []):
            _plan_instance(client_id, client_key, inst, plan, json_path)

    for s in settings:
        _plan_setting(s, plan, json_path)

    return plan


def _plan_branding(client_id, client_key, branding, plan, source):
    where = f"clients[{client_key}].branding"
    if not isinstance(branding, dict):
        raise FileError(f"{where}: must be an object")

    row = {"client_id": client_id}
    for json_field, pg_col in E.CLIENT_BRANDINGS.columns.items():
        if json_field in branding:
            row[pg_col] = branding[json_field]
            
    plan.add(PlanOp(
        spec=E.CLIENT_BRANDINGS,
        pk=client_id,
        payload=row,
        logical_key=(client_key, "branding"),
        source_path=source,
    ))


def _plan_client_texts(client_id, client_key, texts, plan, source):
    """One PlanOp per (channel, locale, key) entry."""
    seen = set()

    for i, entry in enumerate(texts):
        where = f"clients[{client_key}].texts[{i}]"
        if not isinstance(entry, dict):
            raise FileError(f"{where}: must be an object")

        channel    = require(entry, "channel", where)
        text_key   = require(entry, "key", where)
        text_value = entry.get("value")
        locale     = entry.get("locale", "en")
        start_date = entry.get("start_date", "1900-01-01")
        end_date   = entry.get("end_date", "9999-12-31")

        if channel not in ("ask_ai", "live_chat"):
            raise FileError(
                f"{where}.channel: must be 'ask_ai' or 'live_chat', "
                f"got {channel!r}"
            )
        if not isinstance(text_key, str) or not text_key:
            raise FileError(f"{where}.key: must be a non-empty string")
        if not isinstance(text_value, str):
            raise FileError(f"{where}.value: must be a string")
        if not isinstance(locale, str) or not locale:
            raise FileError(f"{where}.locale: must be a non-empty string")

        ident = (channel, locale, text_key, start_date)
        if ident in seen:
            raise FileError(
                f"{where}: duplicate entry for "
                f"channel={channel!r} locale={locale!r} "
                f"key={text_key!r} start_date={start_date!r}"
            )
        seen.add(ident)

        plan.add(PlanOp(
            spec=E.CLIENT_TEXTS,
            pk=None,   # composite; identity is derived from the payload
            payload={
                "client_id":  client_id,
                "channel":    channel,
                "locale":     locale,
                "text_key":   text_key,
                "text_value": text_value,
                "start_date": start_date,
                "end_date":   end_date,
            },
            logical_key=(client_key, "texts", channel, locale, text_key),
            source_path=source,
        ))


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
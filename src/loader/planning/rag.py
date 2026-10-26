"""planning/rag.py - plan builder for the RAG (tenant) DB."""

from loader.entities import rag as E
from loader.planning.website import (
    Plan, PlanOp, read_json, require, resolve_client_id,
)
from loader.errors import FileError


def load_plan(json_path: str, data_root: str) -> Plan:
    payload = read_json(json_path, data_root)
    plan = Plan()

    # 10-client.json can be a bare object, an array, or
    # {"clients": [...]}. Accept all three.
    if isinstance(payload, list):
        clients = payload
    elif isinstance(payload, dict) and "client_key" in payload:
        clients = [payload]
    else:
        clients = payload.get("clients", [])

    for c in clients:
        client_key = require(c, "client_key", "clients")
        cid = resolve_client_id(c, f"clients[{client_key}]")

        # 1. Clients row
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

        # 2. Client texts (one PlanOp per entry)
        texts = c.get("texts", [])
        if not isinstance(texts, list):
            raise FileError(
                f"clients[{client_key}].texts: must be a list, "
                f"got {type(texts).__name__}"
            )

        _plan_client_texts(cid, client_key, texts, plan, json_path)

    return plan


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
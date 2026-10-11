"""
plan.py
Parse a JSON file into a list of PlanOp objects.

A PlanOp is a single row to insert or update. It carries:
  - spec:          EntitySpec
  - pk:            the derived primary key (UUID or natural)
  - payload:       dict of PG column -> value
  - require:       "new" | "existing"
  - logical_key:   tuple identifying the row for error messages
  - source_path:   file location, for error context

The plan module does no I/O beyond reading JSON. It does not touch
the DB. Preflight checks the plan against the DB; write executes it.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from loader import entities
from loader.errors import FileError
from loader.uuid_gen import derive


@dataclass
class PlanOp:
    spec: entities.EntitySpec
    pk: Any
    payload: dict[str, Any]
    require: str
    logical_key: tuple
    source_path: str


@dataclass
class Plan:
    ops: list[PlanOp] = field(default_factory=list)
    refs: dict[tuple[str, str], Any] = field(default_factory=dict)

    def add(self, op: PlanOp):
        self.ops.append(op)


# ---------------------------------------------------------------------

def load_plan(json_path: str, data_root: str) -> Plan:
    path = Path(data_root) / json_path
    if not path.exists():
        raise FileError(f"input file not found: {path}")

    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise FileError(f"invalid JSON in {path}: {e}") from e

    plan = Plan()
    _plan_payload(payload, plan, source=str(path))
    return plan


def _plan_payload(payload: dict, plan: Plan, source: str):
    for client in payload.get("clients", []):
        _plan_client(client, plan, source)

    root = payload.get("root_ad")
    if root:
        _plan_root_ad(root, plan, source)

    matrix = payload.get("ad_matrix")
    if matrix:
        _plan_ad_matrix(matrix, plan, source)

    pricing = payload.get("pricing", {})
    for row in pricing.get("volume_discounts", []):
        _plan_pricing_discount(row, plan, source)
    for row in pricing.get("agency_tier_discounts", []):
        _plan_pricing_discount(row, plan, source)
    for row in pricing.get("negotiated_discounts", []):
        _plan_pricing_discount(row, plan, source)


# ---------------------------------------------------------------------
# clients
# ---------------------------------------------------------------------

def _plan_client(client: dict, plan: Plan, source: str):
    spec = entities.CLIENTS
    key = client["client_key"]
    client_id = derive("client", key)
    plan.refs[("client", key)] = client_id

    require = "new" if client.get("new") else "existing"

    payload = {"client_id": client_id}
    for json_field, pg_col in spec.columns.items():
        if json_field in client:
            payload[pg_col] = client[json_field]

    plan.add(PlanOp(
        spec=spec,
        pk=client_id,
        payload=payload,
        require=require,
        logical_key=(key,),
        source_path=source,
    ))

    msg = client.get("client_messages")
    if msg:
        _plan_client_message(client_id, key, msg, plan, source)

    for wa in client.get("client_whatsapps", []):
        _plan_client_whatsapp(client_id, wa, plan, source)


def _plan_client_message(client_id, client_key, msg, plan, source):
    spec = entities.CLIENT_MESSAGES
    start_date = msg.get("start_date", "1900-01-01")
    pk = derive("client_message", str(client_id), start_date)
    plan.add(PlanOp(
        spec=spec,
        pk=pk,
        payload={
            "client_message_id": pk,
            "client_id": client_id,
            "message_text": msg["message_text"],
            "start_date": start_date,
            "end_date": msg.get("end_date", "9999-12-31"),
        },
        require="new" if msg.get("new") else "existing",
        logical_key=(client_key, "client_messages"),
        source_path=source,
    ))


def _plan_client_whatsapp(client_id, wa, plan, source):
    spec = entities.CLIENT_WHATSAPPS
    phone_id = wa["phone_number_id"]
    plan.add(PlanOp(
        spec=spec,
        pk=phone_id,
        payload={
            "phone_number_id": phone_id,
            "client_id": client_id,
            "display_phone_number": wa["display_phone_number"],
        },
        require="new" if wa.get("new") else "existing",
        logical_key=(phone_id,),
        source_path=source,
    ))


# ---------------------------------------------------------------------
# ads
# ---------------------------------------------------------------------

def _plan_root_ad(root: dict, plan: Plan, source: str):
    client_key = root["client_key"]
    client_id = plan.refs.get(("client", client_key))
    if client_id is None:
        raise FileError(f"root_ad references unknown client_key: {client_key}")

    _plan_ad(
        {
            "source_ad_id": root["source_ad_id"],
            "ad_name": root["ad_name"],
            "is_placeholder": root.get("is_placeholder", True),
            "language_code": root.get("language_code"),
            "reopen_policy": root.get("reopen_policy"),
            "whatsapp_phone_number_id": root.get("whatsapp_phone_number_id"),
            "reuse_root": None,
            "new": root.get("new", False),
        },
        client_id,
        plan, source,
    )

    ad_id = plan.refs[("ad", root["source_ad_id"])]

    if root.get("ad_confirmations"):
        _plan_ad_confirmation(ad_id, root["source_ad_id"],
                              root["ad_confirmations"], plan, source)
    if root.get("ad_reopen_prompts"):
        _plan_ad_reopen_prompt(ad_id, root["source_ad_id"],
                               root["ad_reopen_prompts"], plan, source)
    for faq in root.get("faqs", []):
        _plan_faq(ad_id, root["source_ad_id"], faq, plan, source)
    for band in root.get("qualification_score", []):
        _plan_qualification_score(ad_id, root["source_ad_id"], band, plan, source)


def _plan_ad_matrix(matrix: dict, plan: Plan, source: str):
    client_key = matrix["client_key"]
    client_id = plan.refs.get(("client", client_key))
    if client_id is None:
        raise FileError(f"ad_matrix references unknown client_key: {client_key}")

    root_source_id = matrix["reuse_root"]
    if ("ad", root_source_id) not in plan.refs:
        raise FileError(
            f"ad_matrix.reuse_root '{root_source_id}' has not been planned; "
            f"root_ad must come before ad_matrix"
        )

    channels = matrix["channels"]
    locales = matrix["locales"]
    exclude = set(matrix.get("exclude", []))
    overrides = matrix.get("overrides", {})
    default_new = matrix.get("new", False)

    id_pattern = matrix["source_ad_id_pattern"]
    name_pattern = matrix["ad_name_pattern"]

    for ch in channels:
        for loc in locales:
            key = f"{ch['code']}:{loc}"
            if key in exclude:
                continue

            source_id = id_pattern.format(channel=ch["code"], locale=loc)
            name = name_pattern.format(channel_name=ch["name"], locale=loc)
            is_new = default_new

            if key in overrides:
                o = overrides[key]
                source_id = o.get("source_ad_id", source_id)
                name = o.get("ad_name", name)
                if "new" in o:
                    is_new = o["new"]

            _plan_ad(
                {
                    "source_ad_id": source_id,
                    "ad_name": name,
                    "is_placeholder": matrix.get("is_placeholder", True),
                    "language_code": loc,
                    "whatsapp_phone_number_id": ch.get("whatsapp_phone_number_id"),
                    "reuse_root": root_source_id,
                    "new": is_new,
                },
                client_id,
                plan, source,
            )


def _plan_ad(ad: dict, client_id, plan: Plan, source: str):
    spec = entities.ADS
    source_id = ad["source_ad_id"]
    ad_id = derive("ad", source_id)
    plan.refs[("ad", source_id)] = ad_id

    require = "new" if ad.get("new") else "existing"

    payload = {
        "ad_id": ad_id,
        "client_id": client_id,
        "source_ad_id": source_id,
        "ad_name": ad["ad_name"],
        "is_placeholder": ad.get("is_placeholder", True),
    }
    if ad.get("language_code"):
        payload["language_id"] = ad["language_code"]
    if ad.get("reopen_policy"):
        payload["reopen_policy"] = ad["reopen_policy"]
    if ad.get("whatsapp_phone_number_id"):
        payload["whatsapp_number_id"] = ad["whatsapp_phone_number_id"]

    if ad.get("reuse_root"):
        payload["reuse_ad_id"] = derive("ad", ad["reuse_root"])
        require = "existing"

    plan.add(PlanOp(
        spec=spec,
        pk=ad_id,
        payload=payload,
        require=require,
        logical_key=(source_id,),
        source_path=source,
    ))


def _plan_ad_confirmation(ad_id, source_id, conf, plan, source):
    spec = entities.AD_CONFIRMATIONS
    start_date = conf.get("start_date", "1900-01-01")
    pk = derive("ad_confirmation", str(ad_id), start_date)
    plan.add(PlanOp(
        spec=spec,
        pk=pk,
        payload={
            "ad_confirmation_id": pk,
            "ad_id": ad_id,
            "message_text": conf["message_text"],
            "start_date": start_date,
            "end_date": conf.get("end_date", "9999-12-31"),
        },
        require="new" if conf.get("new") else "existing",
        logical_key=(source_id, "ad_confirmations", start_date),
        source_path=source,
    ))


def _plan_ad_reopen_prompt(ad_id, source_id, prompt, plan, source):
    spec = entities.AD_REOPEN_PROMPTS
    start_date = prompt.get("start_date", "1900-01-01")
    pk = derive("ad_reopen_prompt", str(ad_id), start_date)
    plan.add(PlanOp(
        spec=spec,
        pk=pk,
        payload={
            "ad_reopen_prompt_id": pk,
            "ad_id": ad_id,
            "prompt_text": prompt["prompt_text"],
            "reopen_button_title": prompt["reopen_button_title"],
            "forward_button_title": prompt["forward_button_title"],
            "start_date": start_date,
            "end_date": prompt.get("end_date", "9999-12-31"),
        },
        require="new" if prompt.get("new") else "existing",
        logical_key=(source_id, "ad_reopen_prompts", start_date),
        source_path=source,
    ))


def _plan_faq(ad_id, source_id, faq, plan, source):
    spec = entities.FAQS
    question_id = faq["question_id"]
    start_date = faq.get("start_date", "1900-01-01")
    pk = derive("faq", str(ad_id), str(question_id), start_date)
    plan.add(PlanOp(
        spec=spec,
        pk=pk,
        payload={
            "faq_id": pk,
            "ad_id": ad_id,
            "question_id": question_id,
            "question_order": faq["question_order"],
            "question_text": faq["question_text"],
            "question_type": faq["question_type"],
            "options": faq.get("options"),
            "depends_on": faq.get("depends_on"),
            "mandatory": faq.get("mandatory", True),
            "start_date": start_date,
            "end_date": faq.get("end_date", "9999-12-31"),
        },
        require="new" if faq.get("new") else "existing",
        logical_key=(source_id, "faqs", question_id, start_date),
        source_path=source,
    ))


def _plan_qualification_score(ad_id, source_id, band, plan, source):
    spec = entities.QUALIFICATION_SCORE
    level_code = band["level_code"]
    start_date = band.get("start_date", "1900-01-01")
    pk = derive("qscore", str(ad_id), level_code, start_date)
    plan.add(PlanOp(
        spec=spec,
        pk=pk,
        payload={
            "qualification_score_id": pk,
            "ad_id": ad_id,
            "level_code": level_code,
            "score": band["score_range"],
            "start_date": start_date,
            "end_date": band.get("end_date", "9999-12-31"),
        },
        require="new" if band.get("new") else "existing",
        logical_key=(source_id, "qscore", level_code, start_date),
        source_path=source,
    ))


# ---------------------------------------------------------------------
# pricing
# ---------------------------------------------------------------------

def _plan_pricing_discount(row: dict, plan: Plan, source: str):
    spec = entities.PRICING_DISCOUNTS
    plan.add(PlanOp(
        spec=spec,
        pk=None,
        payload={
            "discount_type": row["discount_type"],
            "leads_min": row.get("leads_min"),
            "leads_max": row.get("leads_max"),
            "discount_pct": row["discount_pct"],
            "label": row["label"],
            "reason": row.get("reason"),
            "start_date": row.get("start_date", "1900-01-01"),
            "end_date": row.get("end_date", "9999-12-31"),
        },
        require="new" if row.get("new") else "existing",
        logical_key=(
            row["discount_type"],
            row.get("leads_min"),
            row.get("leads_max"),
        ),
        source_path=source,
    ))
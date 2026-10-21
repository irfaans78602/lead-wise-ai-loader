"""
plan.py
Parse a JSON file into a list of PlanOp objects.

A PlanOp is a single row to insert or update. It carries:
  - spec:             EntitySpec
  - pk:               the derived primary key (UUID or natural)
  - payload:          dict of PG column -> value
  - logical_key:      tuple identifying the row for error messages
  - source_path:      file location, for error context

Every op is written as "update if the key exists, else insert"
(see write.py). There is no require / "new" / "existing" mode, and
versioned rows are never closed.

The plan module does no I/O beyond reading JSON. It does not touch
the DB. Preflight resolves lookups against the DB; write executes it.

Pricing
-------
Pricing lives inside the client it belongs to:

    "clients": [ { "client_key": "...", ..., "pricing": {
        "volume_discounts": [...],
        "agency_tier_discounts": [...],
        "negotiated_discounts": [...]
    } } ]

The parent client's client_id is attached to "volume" and "negotiated"
rows. "agency_tier" rows are platform-wide (the schema requires
client_id NULL). A top-level "pricing" block is no longer read.

Cross-file client refs
----------------------
A file that carries only ad / matrix data can reference a client that
was loaded from a *different* file by name. Because client UUIDs are
deterministic (`derive("client", client_key)`), the loader computes the
same UUID the earlier file wrote. If the client was never loaded, the
FK on ads.client_id fails at write time.

Encoding
--------
Input JSON is read as UTF-8. Message text, question text and option
labels carry per-locale strings (ar / fr / es / zh / ...), so the file
is never ASCII-only. On Windows, Path.read_text() defaults to the
system locale codec, which cannot decode Arabic; the explicit
encoding="utf-8" here is required, not cosmetic.
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
        payload = json.loads(path.read_text(encoding="utf-8"))
    except UnicodeDecodeError as e:
        raise FileError(
            f"input file is not valid UTF-8: {path} ({e}); "
            f"re-save it as UTF-8"
        ) from e
    except json.JSONDecodeError as e:
        raise FileError(f"invalid JSON in {path}: {e}") from e

    plan = Plan()
    _plan_payload(payload, plan, source=str(path))
    return plan


def _plan_payload(payload: dict, plan: Plan, source: str):
    # Clients first (this also plans each client's messages and pricing).
    for client in payload.get("clients", []):
        _plan_client(client, plan, source)

    # client_users come after clients so optional client_key refs
    # resolve. Users without a client_key are planned with client_id
    # absent and land with NULL, to be linked manually later.
    for user in payload.get("client_users", []):
        _plan_client_user(user, plan, source)

    root = payload.get("root_ad")
    if root:
        _plan_root_ad(root, plan, source)

    matrix = payload.get("ad_matrix")
    if matrix:
        _plan_ad_matrix(matrix, plan, source)


def _resolve_client_ref(plan: Plan, client_key: str):
    """
    Return the client_id for client_key. If the client was planned in
    this same file, use that. Otherwise derive the UUID a prior load
    of 10-clients.json would have produced - the derivation is
    deterministic, so both runs agree.
    """
    client_id = plan.refs.get(("client", client_key))
    if client_id is None:
        client_id = derive("client", client_key)
        plan.refs[("client", client_key)] = client_id
    return client_id


# ---------------------------------------------------------------------
# clients
# ---------------------------------------------------------------------

def _plan_client(client: dict, plan: Plan, source: str):
    spec = entities.CLIENTS
    key = client["client_key"]
    client_id = derive("client", key)
    plan.refs[("client", key)] = client_id

    payload = {"client_id": client_id}
    for json_field, pg_col in spec.columns.items():
        if json_field in client:
            payload[pg_col] = client[json_field]

    plan.add(PlanOp(
        spec=spec,
        pk=client_id,
        payload=payload,
        logical_key=(key,),
        source_path=source,
    ))

    msg = client.get("client_messages")
    if msg:
        _plan_client_message(client_id, key, msg, plan, source)

    pricing = client.get("pricing")
    if pricing:
        _plan_client_pricing(client_id, key, pricing, plan, source)


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
        logical_key=(client_key, "client_messages"),
        source_path=source,
    ))


# ---------------------------------------------------------------------
# pricing (nested under a client)
# ---------------------------------------------------------------------

def _plan_client_pricing(client_id, client_key, pricing, plan, source):
    for group in ("volume_discounts", "agency_tier_discounts",
                  "negotiated_discounts"):
        for row in pricing.get(group, []):
            _plan_pricing_discount(client_id, client_key, row, plan, source)


def _plan_pricing_discount(client_id, client_key, row: dict,
                           plan: Plan, source: str):
    """
    The schema's CHECK on pricing_discounts fixes which columns each
    discount_type may carry:

      volume       client_id optional (set to the parent client);
                   country_id, segment_id, field_name NULL;
                   leads_min/leads_max required.
      agency_tier  client_id NULL; country_id (country_code) set;
                   leads_min/leads_max required.
      negotiated   client_id set (the parent client); segment_id
                   (segment_code), field_name and reason required;
                   leads_min/leads_max NULL.

    The parent's client_id is attached to volume and negotiated rows.
    agency_tier rows stay platform-wide (client_id NULL).
    """
    spec = entities.PRICING_DISCOUNTS
    dtype = row["discount_type"]

    payload: dict[str, Any] = {
        "discount_type": dtype,
        "leads_min": row.get("leads_min"),
        "leads_max": row.get("leads_max"),
        "discount_pct": row["discount_pct"],
        "label": row["label"],
        "reason": row.get("reason"),
        "start_date": row.get("start_date", "1900-01-01"),
        "end_date": row.get("end_date", "9999-12-31"),
    }

    if row.get("country_code"):
        payload["country_id"] = row["country_code"]      # resolved in preflight
    if row.get("segment_code"):
        payload["segment_id"] = row["segment_code"]      # resolved in preflight
    if row.get("field_name"):
        payload["field_name"] = row["field_name"]

    label_key = [dtype, row.get("leads_min"), row.get("leads_max")]

    if dtype == "volume":
        payload["client_id"] = client_id
        label_key = [client_key, dtype, row.get("leads_min"),
                     row.get("leads_max")]
    elif dtype == "negotiated":
        missing = [k for k in ("segment_code", "field_name", "reason")
                   if not row.get(k)]
        if missing:
            raise FileError(
                f"pricing[{client_key}] negotiated '{row['label']}': "
                f"missing {', '.join(missing)}"
            )
        payload["client_id"] = client_id
        label_key = [client_key, dtype, row["segment_code"],
                     row["field_name"]]
    elif dtype == "agency_tier" and not row.get("country_code"):
        raise FileError(
            f"pricing[{client_key}] agency_tier '{row['label']}': "
            f"country_code is required"
        )

    plan.add(PlanOp(
        spec=spec,
        pk=None,
        payload=payload,
        logical_key=tuple(label_key),
        source_path=source,
    ))


# ---------------------------------------------------------------------
# client_users
# ---------------------------------------------------------------------

def _plan_client_user(user: dict, plan: Plan, source: str):
    spec = entities.CLIENT_USERS
    google_sub = user["google_sub"]

    if ("client_user", google_sub) in plan.refs:
        raise FileError(
            f"client_users: duplicate google_sub '{google_sub}' in {source}"
        )
    plan.refs[("client_user", google_sub)] = google_sub

    payload: dict[str, Any] = {"google_sub": google_sub}

    for json_field, pg_col in spec.columns.items():
        if json_field in user:
            payload[pg_col] = user[json_field]

    if not payload.get("email"):
        raise FileError(
            f"client_users[{google_sub}]: 'email' is required"
        )

    # Optional linkage. Absent client_key => row is written with
    # client_id = NULL and linked later by hand. When present, the key
    # string copied above is replaced by the client's UUID.
    client_key = user.get("client_key")
    if client_key is not None:
        client_id = plan.refs.get(("client", client_key))
        if client_id is None:
            raise FileError(
                f"client_users[{google_sub}] references unknown "
                f"client_key: {client_key}"
            )
        payload["client_id"] = client_id

    plan.add(PlanOp(
        spec=spec,
        pk=google_sub,
        payload=payload,
        logical_key=(google_sub,),
        source_path=source,
    ))


# ---------------------------------------------------------------------
# ads
# ---------------------------------------------------------------------

def _plan_root_ad(root: dict, plan: Plan, source: str):
    client_id = _resolve_client_ref(plan, root["client_key"])

    _plan_ad(
        {
            "source_ad_id": root["source_ad_id"],
            "ad_name": root["ad_name"],
            "is_placeholder": root.get("is_placeholder", True),
            "language_code": root.get("language_code"),
            "reopen_policy": root.get("reopen_policy"),
            "reuse_root": None,
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
        _plan_qualification_score(ad_id, root["source_ad_id"], band,
                                  plan, source)


def _plan_ad_matrix(matrix: dict, plan: Plan, source: str):
    client_id = _resolve_client_ref(plan, matrix["client_key"])

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

    id_pattern = matrix["source_ad_id_pattern"]
    name_pattern = matrix["ad_name_pattern"]

    for ch in channels:
        for loc in locales:
            key = f"{ch['code']}:{loc}"
            if key in exclude:
                continue

            source_id = id_pattern.format(channel=ch["code"], locale=loc)
            name = name_pattern.format(channel_name=ch["name"], locale=loc)

            if key in overrides:
                o = overrides[key]
                source_id = o.get("source_ad_id", source_id)
                name = o.get("ad_name", name)

            _plan_ad(
                {
                    "source_ad_id": source_id,
                    "ad_name": name,
                    "is_placeholder": matrix.get("is_placeholder", True),
                    "language_code": loc,
                    "reuse_root": root_source_id,
                },
                client_id,
                plan, source,
            )


def _plan_ad(ad: dict, client_id, plan: Plan, source: str):
    spec = entities.ADS
    source_id = ad["source_ad_id"]
    ad_id = derive("ad", source_id)
    plan.refs[("ad", source_id)] = ad_id

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
    if ad.get("reuse_root"):
        # FK to an already-planned ad; the root is planned earlier in
        # the same file.
        payload["reuse_ad_id"] = derive("ad", ad["reuse_root"])

    plan.add(PlanOp(
        spec=spec,
        pk=ad_id,
        payload=payload,
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
        logical_key=(source_id, "qscore", level_code, start_date),
        source_path=source,
    ))

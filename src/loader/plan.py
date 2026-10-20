"""
plan.py
Parse a JSON file into a list of PlanOp objects.

A PlanOp is a single row to insert or update. It carries:
  - spec:             EntitySpec
  - pk:               the derived primary key (UUID or natural)
  - payload:          dict of PG column -> value
  - require:          "new" | "existing"
  - closes_previous:  for versioned entities, the end_date to stamp on
                      any other current version of the same logical key.
                      None means "infer from start_date".
  - logical_key:      tuple identifying the row for error messages
  - source_path:      file location, for error context

The plan module does no I/O beyond reading JSON. It does not touch
the DB. Preflight checks the plan against the DB; write executes it.

Cross-file client refs
----------------------
A file that carries only ad / matrix / pricing data can reference a
client that was loaded from a *different* file by name. Because client
UUIDs are deterministic (`derive("client", client_key)`), the loader
computes the same UUID the earlier file wrote. If the client was never
loaded, the FK on ads.client_id fails at write time — preflight cannot
detect this because it has no way to know which file the client came
from.

Encoding
--------
Input JSON is read as UTF-8. Message text, question text and option
labels carry per-locale strings (ar / fr / es / zh / …), so the file
is never ASCII-only. On Windows, Path.read_text() defaults to the
system locale codec (cp1252 on most English installs), which cannot
decode Arabic; the explicit encoding="utf-8" here is required, not
cosmetic.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

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
    closes_previous: Optional[str] = None


@dataclass
class Plan:
    ops: list[PlanOp] = field(default_factory=list)
    refs: dict[tuple[str, str], Any] = field(default_factory=dict)

    def add(self, op: PlanOp):
        self.ops.append(op)


# ---------------------------------------------------------------------

def load_plan(json_path: str, data_root: str,
              default_require: str = "existing") -> Plan:
    """
    default_require is applied when the JSON neither sets "new": true
    nor "new": false. Caller picks "new" for seed runs, "existing" for
    updates. Default is "existing" — the safe choice.
    """
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
    _plan_payload(payload, plan, source=str(path),
                  default_require=default_require)
    return plan


def _plan_payload(payload: dict, plan: Plan, source: str,
                  default_require: str):
    for client in payload.get("clients", []):
        _plan_client(client, plan, source, default_require)

    # client_users come after clients so optional client_key refs
    # resolve. Users without a client_key are planned with client_id
    # absent and land with NULL, to be linked manually later.
    for user in payload.get("client_users", []):
        _plan_client_user(user, plan, source, default_require)

    root = payload.get("root_ad")
    if root:
        _plan_root_ad(root, plan, source, default_require)

    matrix = payload.get("ad_matrix")
    if matrix:
        _plan_ad_matrix(matrix, plan, source, default_require)

    pricing = payload.get("pricing", {})
    for row in pricing.get("volume_discounts", []):
        _plan_pricing_discount(row, plan, source, default_require)
    for row in pricing.get("agency_tier_discounts", []):
        _plan_pricing_discount(row, plan, source, default_require)
    for row in pricing.get("negotiated_discounts", []):
        _plan_pricing_discount(row, plan, source, default_require)


def _require_for(obj: dict, default_require: str) -> str:
    """Explicit "new": true|false in the JSON wins; otherwise the
    caller's default.

    The check is on the VALUE, not on key presence. `_plan_root_ad`
    (and the matrix leaf builder) inject "new": None when the JSON
    doesn't say, and a presence check would treat that as an explicit
    `false`, silently overriding the CLI's `--seed` default.
    """
    if obj.get("new") is not None:
        return "new" if obj["new"] else "existing"
    return default_require


def _resolve_client_ref(plan: Plan, client_key: str):
    """
    Return the client_id for client_key. If the client was planned in
    this same file, use that. Otherwise derive the UUID a prior load
    of 10-clients.json would have produced — the derivation is
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

def _plan_client(client: dict, plan: Plan, source: str,
                 default_require: str):
    spec = entities.CLIENTS
    key = client["client_key"]
    client_id = derive("client", key)
    plan.refs[("client", key)] = client_id

    require = _require_for(client, default_require)

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
        _plan_client_message(client_id, key, msg, plan, source,
                             default_require)


def _plan_client_message(client_id, client_key, msg, plan, source,
                         default_require):
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
        require=_require_for(msg, default_require),
        logical_key=(client_key, "client_messages"),
        source_path=source,
        closes_previous=msg.get("closes_previous"),
    ))


# ---------------------------------------------------------------------
# client_users
# ---------------------------------------------------------------------

def _plan_client_user(user: dict, plan: Plan, source: str,
                      default_require: str):
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
    # client_id = NULL and linked later by hand.
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
        require=_require_for(user, default_require),
        logical_key=(google_sub,),
        source_path=source,
    ))


# ---------------------------------------------------------------------
# ads
# ---------------------------------------------------------------------

def _plan_root_ad(root: dict, plan: Plan, source: str,
                  default_require: str):
    client_id = _resolve_client_ref(plan, root["client_key"])

    _plan_ad(
        {
            "source_ad_id": root["source_ad_id"],
            "ad_name": root["ad_name"],
            "is_placeholder": root.get("is_placeholder", True),
            "language_code": root.get("language_code"),
            "reopen_policy": root.get("reopen_policy"),
            "reuse_root": None,
            "new": root.get("new"),
        },
        client_id,
        plan, source, default_require,
    )

    ad_id = plan.refs[("ad", root["source_ad_id"])]

    if root.get("ad_confirmations"):
        _plan_ad_confirmation(ad_id, root["source_ad_id"],
                              root["ad_confirmations"], plan, source,
                              default_require)
    if root.get("ad_reopen_prompts"):
        _plan_ad_reopen_prompt(ad_id, root["source_ad_id"],
                               root["ad_reopen_prompts"], plan, source,
                               default_require)
    for faq in root.get("faqs", []):
        _plan_faq(ad_id, root["source_ad_id"], faq, plan, source,
                  default_require)
    for band in root.get("qualification_score", []):
        _plan_qualification_score(ad_id, root["source_ad_id"], band,
                                  plan, source, default_require)


def _plan_ad_matrix(matrix: dict, plan: Plan, source: str,
                    default_require: str):
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

    # Matrix-level "new" applies to every leaf unless an override says
    # otherwise. Falls back to the CLI default if the matrix doesn't say.
    matrix_new = matrix.get("new")
    matrix_default = (
        "new" if matrix_new else
        "existing" if matrix_new is False else
        default_require
    )

    for ch in channels:
        for loc in locales:
            key = f"{ch['code']}:{loc}"
            if key in exclude:
                continue

            source_id = id_pattern.format(channel=ch["code"], locale=loc)
            name = name_pattern.format(channel_name=ch["name"], locale=loc)
            require = matrix_default

            if key in overrides:
                o = overrides[key]
                source_id = o.get("source_ad_id", source_id)
                name = o.get("ad_name", name)
                if "new" in o:
                    require = "new" if o["new"] else "existing"

            _plan_ad(
                {
                    "source_ad_id": source_id,
                    "ad_name": name,
                    "is_placeholder": matrix.get("is_placeholder", True),
                    "language_code": loc,
                    "reuse_root": root_source_id,
                    "new": None,     # already resolved into require
                },
                client_id,
                plan, source, default_require,
                override_require=require,
            )


def _plan_ad(ad: dict, client_id, plan: Plan, source: str,
             default_require: str, override_require: Optional[str] = None):
    spec = entities.ADS
    source_id = ad["source_ad_id"]
    ad_id = derive("ad", source_id)
    plan.refs[("ad", source_id)] = ad_id

    if override_require is not None:
        require = override_require
    else:
        require = _require_for(ad, default_require)

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
        payload["reuse_ad_id"] = derive("ad", ad["reuse_root"])
        # reuse_ad_id is an FK to an already-planned ad. The root is
        # planned earlier in the same file, so its own PlanOp carries
        # the correct require. Leaves inherit their require from the
        # JSON (or the CLI default) — do NOT override to "existing"
        # here, or fresh seeds fail.

    plan.add(PlanOp(
        spec=spec,
        pk=ad_id,
        payload=payload,
        require=require,
        logical_key=(source_id,),
        source_path=source,
    ))


def _plan_ad_confirmation(ad_id, source_id, conf, plan, source,
                          default_require):
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
        require=_require_for(conf, default_require),
        logical_key=(source_id, "ad_confirmations", start_date),
        source_path=source,
        closes_previous=conf.get("closes_previous"),
    ))


def _plan_ad_reopen_prompt(ad_id, source_id, prompt, plan, source,
                           default_require):
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
        require=_require_for(prompt, default_require),
        logical_key=(source_id, "ad_reopen_prompts", start_date),
        source_path=source,
        closes_previous=prompt.get("closes_previous"),
    ))


def _plan_faq(ad_id, source_id, faq, plan, source, default_require):
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
        require=_require_for(faq, default_require),
        logical_key=(source_id, "faqs", question_id, start_date),
        source_path=source,
        closes_previous=faq.get("closes_previous"),
    ))


def _plan_qualification_score(ad_id, source_id, band, plan, source,
                              default_require):
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
        require=_require_for(band, default_require),
        logical_key=(source_id, "qscore", level_code, start_date),
        source_path=source,
        closes_previous=band.get("closes_previous"),
    ))


# ---------------------------------------------------------------------
# pricing
# ---------------------------------------------------------------------

def _plan_pricing_discount(row: dict, plan: Plan, source: str,
                           default_require: str):
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
        require=_require_for(row, default_require),
        logical_key=(
            row["discount_type"],
            row.get("leads_min"),
            row.get("leads_max"),
        ),
        source_path=source,
    ))
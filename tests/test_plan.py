import json
import tempfile
from pathlib import Path

from loader.plan import load_plan
from loader import entities


def _write_json(tmpdir, name, payload):
    p = Path(tmpdir) / name
    p.write_text(json.dumps(payload))
    return name


def test_minimal_client(tmp_path):
    payload = {
        "clients": [
            {
                "client_key": "acme",
                "new": True,
                "name": "Acme Ltd",
                "email_to": "hi@acme.example",
                "country_code": "ZA",
                "segment_code": "saas_it",
                "currency_code": "ZAR",
                "language_code": "en",
            }
        ]
    }
    name = _write_json(tmp_path, "10.json", payload)
    plan = load_plan(name, str(tmp_path))
    assert len(plan.ops) == 1
    op = plan.ops[0]
    assert op.spec.table == "clients"
    assert op.require == "new"
    assert op.payload["name"] == "Acme Ltd"
    assert op.payload["country_id"] == "ZA"   # resolved to ID at preflight


def test_root_ad_with_faqs(tmp_path):
    payload = {
        "clients": [
            {
                "client_key": "acme", "new": True, "name": "Acme",
                "email_to": "a@b.c", "language_code": "en",
                "country_code": "ZA", "segment_code": "saas_it",
                "currency_code": "ZAR",
            }
        ],
        "root_ad": {
            "client_key": "acme",
            "new": True,
            "source_ad_id": "acme-web",
            "ad_name": "Acme Web",
            "language_code": "en",
            "reuse_root": None,
            "faqs": [
                {
                    "new": True,
                    "question_id": 10,
                    "question_order": 1,
                    "question_text": {"en": "Name?"},
                    "question_type": "first_name",
                    "mandatory": True,
                }
            ],
        },
    }
    name = _write_json(tmp_path, "60.json", payload)
    plan = load_plan(name, str(tmp_path))
    tables = [op.spec.table for op in plan.ops]
    assert "clients" in tables
    assert "ads" in tables
    assert "faqs" in tables
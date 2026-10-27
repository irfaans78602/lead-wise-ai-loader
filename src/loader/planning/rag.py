"""planning/rag.py - plan builder for the RAG (tenant) DB."""

from loader.planning.website import Plan

def load_plan(json_path: str, data_root: str) -> Plan:
    # The RAG DB is populated via tools/ingest_rag.py, not the JSON loader.
    # Return an empty plan so the CLI doesn't crash if accidentally invoked.
    return Plan()
"""entities/rag.py - RAG (tenant) DB entity specs."""

from loader.entities import EntitySpec

# The RAG DB is populated via the ingestion script (tools/ingest_rag.py).
# There are currently no JSON entities to load directly into the RAG DB.
ALL = {}
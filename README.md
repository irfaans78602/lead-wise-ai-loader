# lead-wise-ai-loader

Loads per-client JSON into the LeadWise AI Postgres database.

Two modes:
- **Preview** (default): runs the full transaction, reads back the projected
  state, writes a log, then rolls back. Nothing is committed.
- **Commit** (`--commit`): same transaction, commits at the end.

Preview and commit produce byte-identical logs except for `mode:` in the
header and the final transaction verb. Diffing them proves a commit did
exactly what its preview said it would.

## Repos this loader touches

| Repo | Role | Env var |
|---|---|---|
| `lead-wise-ai-schema` | DDL and base seeds | `LW_SCHEMA_ROOT` |
| `lead-wise-ai-data` | Per-client JSON, logs | `LW_DATA_ROOT` |

Neither is required for a pure load against an already-built DB. They are
required for `db` subcommands.

## Install

    pip install -e .

## Usage

    # Preview a client's instance data (writes nothing)
    python -m loader clients/leadwise-ai/60-instance.json

    # Commit
    python -m loader clients/leadwise-ai/60-instance.json --commit

    # Schema management
    python -m loader db drop
    python -m loader db create
    python -m loader db seed
    python -m loader db rebuild

## Env vars

    DATABASE_URL        postgres://...
    LW_DATA_ROOT        path to lead-wise-ai-data (default: cwd)
    LW_SCHEMA_ROOT      path to lead-wise-ai-schema (default: ../lead-wise-ai-schema)

See `docs/decision-34-loader-json-semantics.md` in the docs repo for the
JSON format and the "new" marker semantics.
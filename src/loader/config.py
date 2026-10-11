"""
config.py
Reads and validates configuration from environment and CLI.
"""

import os
from dataclasses import dataclass
from loader.errors import ConfigError


DEFAULT_SCHEMA_ROOT = "../lead-wise-ai-schema"


@dataclass(frozen=True)
class Config:
    database_url: str
    data_root: str
    schema_root: str


def load(data_root: str | None = None, schema_root: str | None = None) -> Config:
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        raise ConfigError("DATABASE_URL is not set")

    data = data_root or os.environ.get("LW_DATA_ROOT") or os.getcwd()
    schema = schema_root or os.environ.get("LW_SCHEMA_ROOT") or DEFAULT_SCHEMA_ROOT

    return Config(
        database_url=db_url,
        data_root=os.path.abspath(data),
        schema_root=os.path.abspath(schema),
    )
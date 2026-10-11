"""
config.py
Reads and validates configuration from environment and CLI.

Loads a .env file, in this order of precedence:

  1. $LW_ENV_FILE, if set -- an explicit path, for tests and CI.
  2. <loader_repo_root>/.env -- the canonical location. The loader's
     own config lives with the loader, regardless of which directory
     you run it from.
  3. Nearest .env walking up from cwd -- a fallback for operators who
     prefer per-project config.

Real environment variables always win over .env -- this is a
convenience, not a source of truth.
"""

import os
from dataclasses import dataclass
from pathlib import Path

from loader.errors import ConfigError


DEFAULT_SCHEMA_ROOT = "../lead-wise-ai-schema"
_DOTENV_NAME = ".env"
_LOADED_FLAG = "_lw_dotenv_loaded"


def _loader_repo_root() -> Path:
    """The lead-wise-ai-loader checkout root.

    config.py sits at <root>/src/loader/config.py, so three parents
    up from this file is the repo root.
    """
    return Path(__file__).resolve().parent.parent.parent


def _load_dotenv():
    if os.environ.get(_LOADED_FLAG):
        return
    os.environ[_LOADED_FLAG] = "1"

    # 1. Explicit override.
    explicit = os.environ.get("LW_ENV_FILE")
    if explicit:
        p = Path(explicit)
        if p.is_file():
            _parse_dotenv(p)
            return

    # 2. The loader's own .env -- preferred.
    repo_env = _loader_repo_root() / _DOTENV_NAME
    if repo_env.is_file():
        _parse_dotenv(repo_env)
        return

    # 3. Walk up from cwd.
    path = Path.cwd()
    while True:
        candidate = path / _DOTENV_NAME
        if candidate.is_file():
            _parse_dotenv(candidate)
            return
        if path.parent == path:
            return
        path = path.parent


def _parse_dotenv(path: Path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key and key not in os.environ:
            os.environ[key] = value


@dataclass(frozen=True)
class Config:
    database_url: str
    data_root: str
    schema_root: str


def load(data_root: str | None = None, schema_root: str | None = None) -> Config:
    _load_dotenv()

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
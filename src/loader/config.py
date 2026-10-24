"""
config.py
Reads and validates configuration from environment and CLI.

Three profiles are supported - master, rag, website - each configured
from a dedicated .env file:

    .env.master      MASTER_*
    .env.rag         RAG_*
    .env.website     WEBSITE_*

Plus one loader-only file with no profile prefix:

    .env.loader      LW_*

Per-profile variables (PREFIX = MASTER | RAG | WEBSITE):

    <PREFIX>_DATABASE_URL              required to enable the profile
    <PREFIX>_DATA_ROOT                 default ./data/<profile>
    <PREFIX>_SCHEMA_ROOT               default ./schema/<profile>
    <PREFIX>_EXPECTED_SCHEMA_VERSION   optional integer

Precedence (earlier wins; real environment variables always win):
  1. real environment variables
  2. <repo_root>/.env.loader
  3. <repo_root>/.env.master
  4. <repo_root>/.env.rag
  5. <repo_root>/.env.website

(Files are read in the order 2-5 and a key is only set if it is not
already in the environment, so the first definition of a key wins.)

A profile whose <PREFIX>_DATABASE_URL is unset is absent from
`Config.profiles`. LW_ENV_DIR (tests/CI) replaces <repo_root> as the
directory the four .env files are read from.
"""

import os
from dataclasses import dataclass
from pathlib import Path

from loader.errors import ConfigError


_PROFILE_NAMES = ("master", "rag", "website")
_ENV_FILES = (".env.loader", ".env.master", ".env.rag", ".env.website")

_LOADED_FLAG = "_lw_dotenv_loaded"


def _loader_repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def _load_all_dotenvs():
    if os.environ.get(_LOADED_FLAG):
        return
    os.environ[_LOADED_FLAG] = "1"
    explicit = os.environ.get("LW_ENV_DIR")
    base = Path(explicit) if explicit else _loader_repo_root()
    for name in _ENV_FILES:
        path = base / name
        if path.is_file():
            _parse_dotenv(path)


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
class Profile:
    name: str
    database_url: str
    data_root: str
    schema_root: str
    expected_schema_version: int | None

    @property
    def env_prefix(self) -> str:
        return self.name.upper()


@dataclass(frozen=True)
class Config:
    profiles: dict[str, Profile]
    default_profile: str

    def get(self, name: str | None = None) -> Profile:
        name = name or self.default_profile
        if name not in self.profiles:
            raise ConfigError(
                f"unknown profile '{name}'; "
                f"known: {', '.join(sorted(self.profiles))}"
            )
        return self.profiles[name]


def load(
    profile: str | None = None,
    data_root: str | None = None,
    schema_root: str | None = None,
) -> Config:
    _load_all_dotenvs()
    profiles: dict[str, Profile] = {}

    for name in _PROFILE_NAMES:
        prefix = name.upper()
        db_url = os.environ.get(f"{prefix}_DATABASE_URL")
        if not db_url:
            continue

        profiles[name] = Profile(
            name=name,
            database_url=db_url,
            data_root=_abspath(
                data_root
                or os.environ.get(f"{prefix}_DATA_ROOT")
                or f"./data/{name}"
            ),
            schema_root=_abspath(
                schema_root
                or os.environ.get(f"{prefix}_SCHEMA_ROOT")
                or f"./schema/{name}"
            ),
            expected_schema_version=_int_or_none(
                os.environ.get(f"{prefix}_EXPECTED_SCHEMA_VERSION")
            ),
        )

    if not profiles:
        raise ConfigError(
            "no profiles configured: set MASTER_DATABASE_URL, "
            "RAG_DATABASE_URL, and/or WEBSITE_DATABASE_URL"
        )

    default = (
        profile
        or os.environ.get("LW_DEFAULT_PROFILE")
        or next(iter(profiles))
    )
    if default not in profiles:
        raise ConfigError(
            f"default profile '{default}' has no DATABASE_URL; "
            f"set {default.upper()}_DATABASE_URL"
        )

    return Config(profiles=profiles, default_profile=default)


def _abspath(p: str) -> str:
    return os.path.abspath(os.path.expanduser(p))


def _int_or_none(v: str | None) -> int | None:
    if v is None or v == "":
        return None
    try:
        return int(v)
    except ValueError as e:
        raise ConfigError(f"expected integer, got {v!r}") from e
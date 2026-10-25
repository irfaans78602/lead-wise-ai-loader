from dataclasses import dataclass, field

@dataclass(frozen=True)
class EntitySpec:
    name: str
    table: str
    pk_col: str
    pk_kind: str
    natural_key: tuple[str, ...]
    versioned: bool = False
    version_key: tuple[str, ...] = ()
    columns: dict[str, str] = field(default_factory=dict)
    parent_refs: dict[str, tuple[str, str]] = field(default_factory=dict)
    # Columns written on INSERT only. On conflict they are left as they
    # are in the database (for example counters the platform maintains).
    insert_only: tuple[str, ...] = ()

from loader.entities import website, master, rag  # noqa: E402

_REGISTRIES = {
    "master":   master,
    "rag":      rag,
    "website": website,
}

def for_profile(name: str):
    if name not in _REGISTRIES:
        raise ValueError(f"no entity registry for profile '{name}'")
    return _REGISTRIES[name]

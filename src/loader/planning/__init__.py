"""planning - profile -> planner function."""

from loader.planning import website, master, rag

# Each value is a callable: load_plan(json_path, data_root) -> Plan
_PLANNERS = {
    "master":       master.load_plan,
    "rag":          rag.load_plan,
    "website":      website.load_plan,
    "website_demo": website.load_plan,
}


def for_profile(name: str):
    if name not in _PLANNERS:
        raise ValueError(f"no planner for profile '{name}'")
    return _PLANNERS[name]


def load_many(name: str, json_paths, data_root: str):
    """
    Plan several input files as ONE plan, so they run in one
    transaction. Ops keep file order, then in-file order, which is what
    makes a later file's rows able to reference an earlier file's rows
    (e.g. ads -> clients) before anything is committed.
    """
    planner = for_profile(name)
    merged = None
    for path in json_paths:
        plan = planner(path, data_root)
        if merged is None:
            merged = plan
        else:
            merged.ops.extend(plan.ops)
            merged.refs.update(plan.refs)
    return merged
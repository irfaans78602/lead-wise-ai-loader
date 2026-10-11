"""
log.py
Writes the per-run log. Every run (preview or commit) produces one
file. The file is the artifact; stdout is a three-line glance.

Log path:
    {data_root}/logs/{client_slug}/{YYYY-MM-DD-HHMMSS}-{mode}.log

Client slug resolution, in order:
  1. .client-slug next to the input JSON — a one-line file whose
     contents are the slug. Use this when the folder name and the
     slug should differ (e.g. "LeadWiseAI" folder, "leadwise-platform"
     slug).
  2. First path segment of the input path — the folder name itself.
     Use this when the folder name is already a valid slug.
  3. "unknown" — the input file sits at data_root with no subfolder.
"""

import os
import re
from datetime import datetime, timezone
from pathlib import Path


# Legacy clients/<slug>/ pattern, kept as a secondary fallback for
# repos that still use it.
CLIENT_PATH_RE = re.compile(r"(?:^|/)clients/([^/]+)/")


def client_slug(data_root: str, input_path: str) -> str:
    """
    Resolve the slug used for the log directory name.

    See the module docstring for the resolution order.
    """
    json_path = Path(input_path)

    # 1. .client-slug next to the input file.
    slug_file = Path(data_root) / json_path.parent / ".client-slug"
    if slug_file.exists():
        content = slug_file.read_text(encoding="utf-8").strip()
        if content:
            return content

    # 2. Legacy clients/<slug>/ pattern anywhere in the path.
    normalized = input_path.replace(os.sep, "/")
    m = CLIENT_PATH_RE.search(normalized)
    if m:
        return m.group(1)

    # 3. First path segment, if the file lives in a subfolder.
    parts = normalized.strip("/").split("/")
    if len(parts) >= 2:
        return parts[0]

    # 4. Nothing to derive from.
    return "unknown"


class RunLog:
    def __init__(self, data_root: str, input_path: str, mode: str):
        self.mode = mode
        slug = client_slug(data_root, input_path)
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%d-%H%M%S")
        log_dir = Path(data_root) / "logs" / slug
        log_dir.mkdir(parents=True, exist_ok=True)
        self.path = log_dir / f"{ts}-{mode}.log"
        self._fh = self.path.open("w", encoding="utf-8")
        self._t0 = datetime.now(timezone.utc)

    def _elapsed(self) -> str:
        delta = datetime.now(timezone.utc) - self._t0
        return f"[+{delta.total_seconds():.3f}s]"

    def header(self, *, input_path: str, database_url: str,
               schema_version: int | None, expected_schema_version: int,
               loader_version: str, file_sha256: str):
        started = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        db_clean = _redact_database_url(database_url)
        self._fh.write("=== load_run ===\n")
        self._fh.write(f"started:     {started}\n")
        self._fh.write(f"mode:        {self.mode}\n")
        self._fh.write(f"input:       {input_path}\n")
        self._fh.write(f"file_sha256: {file_sha256}\n")
        self._fh.write(f"database:    {db_clean}\n")
        self._fh.write(f"schema_ver:  {schema_version} (expected {expected_schema_version})\n")
        self._fh.write(f"loader_ver:  {loader_version}\n\n")
        self._fh.flush()

    def section(self, title: str):
        self._fh.write(f"--- {title} ---   {self._elapsed()}\n")

    def line(self, text: str):
        self._fh.write(text + "\n")

    def changes(self, pre: dict, post: dict):
        """
        pre, post: outputs of diff.read_state(). Both keyed by
        {table: {row_identity: row_dict}}.

        For each table, print:
          INSERT    <identity>       present in post, absent in pre
          UPDATE    <identity>       present in both, columns differ
          UNCHANGED <identity>       present in both, columns same
        """
        self._fh.write(f"--- changes ---   {self._elapsed()}\n\n")

        tables = sorted(set(pre) | set(post))
        for table in tables:
            pre_rows = pre.get(table, {})
            post_rows = post.get(table, {})
            ids = sorted(set(pre_rows) | set(post_rows))

            self._fh.write(f"== {table} ==\n")
            for rid in ids:
                if rid not in pre_rows:
                    self._fh.write(f"INSERT    {rid}\n")
                    self._write_cols(post_rows[rid], indent="    ")
                elif rid not in post_rows:
                    # Row was deleted mid-transaction. Not expected in
                    # the loader's model; flag it.
                    self._fh.write(f"DELETED   {rid}\n")
                else:
                    diffs = _diff_rows(pre_rows[rid], post_rows[rid])
                    if diffs:
                        self._fh.write(f"UPDATE    {rid}\n")
                        for col, before, after in diffs:
                            self._fh.write(f"    {col}: {_fmt(before)}  ->  {_fmt(after)}\n")
                    else:
                        self._fh.write(f"UNCHANGED {rid}\n")
            self._fh.write("\n")
        self._fh.flush()

    def _write_cols(self, row: dict, indent: str):
        for col in sorted(row.keys()):
            if col.endswith("_id"):
                continue
            v = row[col]
            if v is None or v == "":
                continue
            self._fh.write(f"{indent}{col}: {_fmt(v)}\n")

    def summary(self, counts: dict):
        self._fh.write(f"--- summary ---   {self._elapsed()}\n")
        width = max((len(k) for k in counts), default=0) + 1
        for table in sorted(counts):
            c = counts[table]
            line = (
                f"{table + ':':<{width}} "
                f"{c['inserted']} inserted, "
                f"{c['updated']} updated, "
                f"{c['unchanged']} unchanged"
            )
            if c.get("extra"):
                line += f" ({c['extra']})"
            self._fh.write(line + "\n")
        self._fh.write("\n")

    def footer(self, *, result: str, exit_code: int):
        finished = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        delta = datetime.now(timezone.utc) - self._t0
        self._fh.write(f"result:    {result}\n")
        self._fh.write(f"exit:      {exit_code}\n")
        self._fh.write(f"finished:  {finished}\n")
        self._fh.write(f"duration:  {delta.total_seconds():.3f}s\n")

    def close(self):
        self._fh.close()


def file_hash(path: str) -> str:
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _diff_rows(pre: dict, post: dict) -> list[tuple[str, object, object]]:
    """Return [(col, before, after)] for every column that changed."""
    out = []
    for col in sorted(set(pre) | set(post)):
        b = pre.get(col)
        a = post.get(col)
        if _compare(b, a):
            continue
        out.append((col, b, a))
    return out


def _compare(a, b) -> bool:
    """Structural equality that treats None and empty-string as the
    same 'absent' value for diff purposes."""
    if a is None and b in (None, ""):
        return True
    if b is None and a in (None, ""):
        return True
    return a == b


def _fmt(v) -> str:
    if v is None:
        return "NULL"
    s = str(v)
    if len(s) > 80:
        return s[:77] + "..."
    return s


def _redact_database_url(url: str) -> str:
    if "@" not in url:
        return url
    scheme, rest = url.split("://", 1) if "://" in url else ("", url)
    creds, tail = rest.rsplit("@", 1)
    user = creds.split(":", 1)[0]
    return f"{scheme}://{user}@{tail}" if scheme else f"{user}@{tail}"
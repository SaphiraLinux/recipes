#!/usr/bin/python3

"""repo-db.py — shared repository metadata library (SQLite, single-file).

One repo-local database per generation repository::

    /out/stage4/packages/<generation>/<arch>/repository.db

replaces both ``ownership.json`` (file ownership) and ``accounts.json``
(account registry) with a normalized relational schema. Humans never
write SQL: ``saphira-repo-state`` is the read interface.

Sanctioned WRITERS (same DB lock + this library + same validation and
fingerprint transaction rules — no miscellaneous SQLite-writing paths):
    sign-apk-repo, saphira-repo-migrate (migrate + --reconcile),
    promote-repo, seed-repo.
``saphira-repo-state`` is permanently read-only: it uses connect_readonly
plus the query helpers only, and this module exposes no write path that
does not require an explicit read-write connection.

controller state and repository metadata remain separate: nothing here
ever opens the controller database.

Single-file durability: repositories get copied and synced, so there
must never be -wal/-shm sidecars. Exactly one real writer and occasional
readers; portability beats WAL concurrency::

    PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;
    PRAGMA foreign_keys=ON;   PRAGMA busy_timeout=30000;

Terminology (kept unambiguous on purpose): an "APK identity" is a
published (name, version) package. A "Unix identity" is a user/group
account declaration. Outputs always say which one is meant.

Eternal reservations: ``reservations`` rows are NEVER deleted. Dropping
a fragment ends active ownership but tombstones the binding instead of
freeing it. The same package lineage may later reclaim its canonical
ID; an unrelated identity may never reuse it. ``--full-audit`` (and
``--reconcile``) on a current-view repository reconstructs current
packages/files/accounts and VERIFIES reservations — it never
destroys or recreates the reservation ledger from current-only state.
A missing reservation history requires explicit recovery from the
authoritative append-only history (hatchling) or migration evidence,
never inference. Only a census over complete append-only history may
re-derive tombstones (``--from-history``).
"""

from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from functools import cmp_to_key
from pathlib import Path
from typing import NoReturn

SCHEMA_VERSION = "saphira-repository.db/v1"
FRAGMENT_PREFIX = "usr/share/saphira/accounts.d/"
EMPTY_DECL = {"users": [], "groups": [], "dirs": [], "files": []}

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
VERSION_BASE_RE = re.compile(r"^(?P<base>.+)-r(?P<rel>\d+)$")
DIR_RE = re.compile(r"^  - name: (\S+)$")
FILE_RE = re.compile(r"^      - name: (\S+)$")
TOP_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_.-]*):")
DEP_ATOM_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*")


def die(message: str) -> NoReturn:
    raise RepoDbError(message)


class RepoDbError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# makepkg import: the fragment parser and the range/reservation constants
# have exactly one home (makepkg). This library reuses them so build-time
# validation and publish-time gating can never drift apart.
# ---------------------------------------------------------------------------

_MAKEPKG = None


def makepkg():
    global _MAKEPKG
    if _MAKEPKG is not None:
        return _MAKEPKG
    here = Path(__file__).resolve().parent
    candidates = [here / "makepkg", Path("/usr/bin/makepkg")]
    for candidate in candidates:
        if candidate.is_file():
            loader = importlib.machinery.SourceFileLoader("saphira_makepkg", str(candidate))
            spec = importlib.util.spec_from_file_location(
                "saphira_makepkg", str(candidate), loader=loader)
            if spec is None or spec.loader is None:
                continue
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            _MAKEPKG = module
            return module
    raise RepoDbError("cannot locate makepkg for fragment validation")


# ---------------------------------------------------------------------------
# connections
# ---------------------------------------------------------------------------

def connect(db_path: str | Path, readonly: bool = False) -> sqlite3.Connection:
    if readonly:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("PRAGMA busy_timeout=30000")
    else:
        conn = sqlite3.connect(str(db_path), timeout=30.0, isolation_level=None)
        conn.execute("PRAGMA journal_mode=DELETE")
        conn.execute("PRAGMA synchronous=FULL")
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("PRAGMA busy_timeout=30000")
    conn.row_factory = sqlite3.Row
    return conn


def connect_readonly(db_path: str | Path) -> sqlite3.Connection:
    return connect(db_path, readonly=True)


DDL = """
CREATE TABLE IF NOT EXISTS metadata(
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS packages(
    package_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    pkgrel INTEGER NOT NULL,
    nvr TEXT NOT NULL,
    apk_sha256 TEXT NOT NULL,
    is_newest INTEGER NOT NULL,
    published_at TEXT,
    UNIQUE(name, version)
);
CREATE INDEX IF NOT EXISTS idx_packages_name ON packages(name);
CREATE TABLE IF NOT EXISTS files(
    package_id INTEGER NOT NULL REFERENCES packages(package_id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    PRIMARY KEY(package_id, path)
);
CREATE INDEX IF NOT EXISTS idx_files_path ON files(path);
CREATE TABLE IF NOT EXISTS users(
    package_id INTEGER NOT NULL REFERENCES packages(package_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    uid INTEGER NOT NULL,
    primary_group TEXT NOT NULL,
    home TEXT NOT NULL,
    shell TEXT NOT NULL,
    declaration_sha256 TEXT NOT NULL,
    PRIMARY KEY(package_id, name)
);
CREATE INDEX IF NOT EXISTS idx_users_name ON users(name);
CREATE INDEX IF NOT EXISTS idx_users_uid ON users(uid);
CREATE TABLE IF NOT EXISTS groups(
    package_id INTEGER NOT NULL REFERENCES packages(package_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    gid INTEGER NOT NULL,
    declaration_sha256 TEXT NOT NULL,
    PRIMARY KEY(package_id, name)
);
CREATE INDEX IF NOT EXISTS idx_groups_name ON groups(name);
CREATE INDEX IF NOT EXISTS idx_groups_gid ON groups(gid);
CREATE TABLE IF NOT EXISTS state_dirs(
    package_id INTEGER NOT NULL REFERENCES packages(package_id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    mode TEXT NOT NULL,
    owner TEXT NOT NULL,
    "group" TEXT NOT NULL,
    PRIMARY KEY(package_id, path)
);
CREATE TABLE IF NOT EXISTS reservations(
    kind TEXT NOT NULL CHECK(kind IN ('user', 'group')),
    name TEXT NOT NULL,
    numeric_id INTEGER NOT NULL,
    owning_package TEXT NOT NULL,
    first_nvr TEXT NOT NULL,
    last_nvr TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('ACTIVE', 'TOMBSTONED')),
    declaration_sha256 TEXT NOT NULL,
    PRIMARY KEY(kind, name),
    UNIQUE(kind, numeric_id)
);
"""


def init_db(conn: sqlite3.Connection, repo_name: str, history_complete: bool) -> None:
    conn.executescript(DDL)
    conn.execute(
        "INSERT OR REPLACE INTO metadata(key, value) VALUES "
        "('schema_version', ?), ('repo_name', ?), ('history_complete', ?)",
        (SCHEMA_VERSION, repo_name, "1" if history_complete else "0"),
    )


def check_schema(conn: sqlite3.Connection) -> None:
    row = conn.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()
    if row is None or row["value"] != SCHEMA_VERSION:
        raise RepoDbError(
            f"repository.db schema mismatch (want {SCHEMA_VERSION}); "
            "run saphira-repo-migrate --reconcile"
        )


def set_meta(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute("INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)", (key, value))


def get_meta(conn: sqlite3.Connection, key: str) -> str | None:
    row = conn.execute("SELECT value FROM metadata WHERE key=?", (key,)).fetchone()
    return row["value"] if row else None


# ---------------------------------------------------------------------------
# canonical declarations
# ---------------------------------------------------------------------------

def canonical_declaration(users: list, groups: list, dirs: list) -> tuple[str, str]:
    doc = {
        "users": sorted(
            (
                {
                    "name": u["name"],
                    "uid": str(int(u["uid"])),
                    "primary": u["primary"],
                    "home": u["home"],
                    "shell": u["shell"],
                }
                for u in users
            ),
            key=lambda u: u["name"],
        ),
        "groups": sorted(
            ({"name": g["name"], "gid": str(int(g["gid"]))} for g in groups),
            key=lambda g: g["name"],
        ),
        "dirs": sorted(
            (
                {"path": d["path"], "mode": d["mode"], "owner": d["owner"], "group": d["group"]}
                for d in dirs
            ),
            key=lambda d: d["path"],
        ),
    }
    text = json.dumps(doc, sort_keys=True, separators=(",", ":"))
    return text, hashlib.sha256(text.encode()).hexdigest()


def empty_declaration_sha() -> str:
    return canonical_declaration([], [], [])[1]


# ---------------------------------------------------------------------------
# APK introspection (same dump semantics as the publication gate)
# ---------------------------------------------------------------------------

def unfold_names(lines: list[str]) -> list[str]:
    out: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        match = re.match(r"^(\s*)- name: ([|>])\s*$", line)
        if match is None:
            out.append(line)
            index += 1
            continue
        indent = len(match.group(1))
        key_indent = indent + 2
        joiner = "" if match.group(2) == "|" else " "
        parts: list[str] = []
        index += 1
        while index < len(lines):
            cont = lines[index]
            if cont.strip() == "" or len(cont) - len(cont.lstrip()) <= key_indent:
                break
            parts.append(cont.strip())
            index += 1
        out.append(f"{' ' * indent}- name: {joiner.join(parts)}")
    return out


def dump_package(apk_bin: str, apk_path: str | Path) -> dict:
    dump = subprocess.run(
        [apk_bin, "adbdump", str(apk_path)],
        check=True, text=True, capture_output=True,
    ).stdout
    name = version = None
    files: list[str] = []
    replaces: set[str] = set()
    depends: list[str] = []
    section, cur, in_list = None, None, None
    for line in unfold_names(dump.splitlines()):
        top = TOP_RE.match(line)
        if top:
            section, cur, in_list = top.group(1), None, None
            continue
        if section == "info":
            if re.match(r"^  replaces:", line):
                in_list = "replaces"
                continue
            if re.match(r"^  depends:", line):
                in_list = "depends"
                continue
            if in_list == "replaces":
                m = re.match(r"^    +- (\S+)$", line) or re.match(r"^    +- name: (\S+)$", line)
                if m:
                    replaces.add(m.group(1))
                    continue
                if re.match(r"^  \S", line):
                    in_list = None
            elif in_list == "depends":
                m = re.match(r"^    +- (\S+)$", line) or re.match(r"^    +- name: (\S+)$", line)
                if m:
                    depends.append(m.group(1))
                    continue
                if re.match(r"^  \S", line):
                    in_list = None
            m = re.match(r"^  name: (\S+)$", line)
            if m:
                name = m.group(1)
            m = re.match(r"^  version: (\S+)$", line)
            if m:
                version = m.group(1)
        elif section == "paths":
            m = DIR_RE.match(line)
            if m:
                cur = m.group(1)
                continue
            m = FILE_RE.match(line)
            if m and cur:
                files.append(f"{cur}/{m.group(1)}")
    if not name or not version:
        raise RepoDbError(f"cannot read package identity: {apk_path}")
    return {"name": name, "version": version, "files": files,
            "replaces": sorted(replaces), "depends": depends}


def apk_newer(apk_bin: str, a: str, b: str) -> bool:
    out = subprocess.run(
        [apk_bin, "version", "-t", a, b],
        check=True, text=True, capture_output=True,
    ).stdout.strip()
    return out == ">"


def pkgrel_of(version: str) -> int:
    match = VERSION_BASE_RE.fullmatch(version)
    if not match:
        raise RepoDbError(f"version has no -rN pkgrel: {version}")
    return int(match.group("rel"))


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# census: the deliberate expensive pass (migration, --full-audit, reconcile)
# ---------------------------------------------------------------------------

def census(apk_bin: str, repo_dir: str | Path) -> dict[str, dict]:
    """Dump every repository APK. Returns {filename: info} with info holding
    name, version, files, replaces, depends and apk_sha256. Dumps run in a
    thread pool (subprocess + hashing release the GIL; results collected
    in sorted order, so output is deterministic and the first failure
    still fails the whole census closed)."""
    import concurrent.futures
    paths = sorted(
        path for path in Path(repo_dir).glob("*.apk")
        if not path.is_symlink() and path.is_file()
    )

    def dump_one(path):
        info = dump_package(apk_bin, path)
        info["apk_sha256"] = sha256_file(path)
        return path.name, info

    result: dict[str, dict] = {}
    workers = min(8, (os.cpu_count() or 1) + 4)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for name, info in pool.map(dump_one, paths):
            result[name] = info
    return result


def fragment_carriers(census_data: dict[str, dict]) -> list[str]:
    return sorted(
        filename for filename, info in census_data.items()
        if any(f.startswith(FRAGMENT_PREFIX) for f in info["files"])
    )


def extract_declarations(apk_bin: str, repo_dir: str | Path, filenames: list[str],
                         work_tmp: str | Path) -> dict[str, dict]:
    """Read account declarations from carrier payloads via an isolated
    tmp-root install (dependency closure resolved offline from the same
    repository). Returns {filename: declaration}. Carriers only — never
    a full-repository extraction."""
    if not filenames:
        return {}
    repo_dir = Path(repo_dir)
    work_tmp = Path(work_tmp)
    _dump_cache: dict[str, dict] = {}

    def cached_dump(filename: str) -> dict:
        if filename not in _dump_cache:
            _dump_cache[filename] = dump_package(apk_bin, repo_dir / filename)
        return _dump_cache[filename]

    def newest_provider(pkgname: str) -> str:
        matches = []
        for path in repo_dir.glob(f"{pkgname}-*.apk"):
            if not path.is_file() or path.is_symlink():
                continue
            info = cached_dump(path.name)
            # Filename prefix is not identity: gdbm-*.apk also matches
            # gdbm-dev-*.apk. Only the exact package name provides it.
            if info["name"] == pkgname:
                matches.append(path.name)
        if not matches:
            raise RepoDbError(
                f"cannot resolve dependency {pkgname} for declaration extraction"
                " (rebuild and re-publish the package)"
            )
        best = matches[0]
        for candidate in matches[1:]:
            if apk_newer(apk_bin, cached_dump(candidate)["version"],
                         cached_dump(best)["version"]):
                best = candidate
        return best

    closure = set(filenames)
    queue = list(filenames)
    while queue:
        current = queue.pop()
        for atom in cached_dump(current)["depends"]:
            bare = atom.split("<")[0].split(">")[0].split("=")[0].split("~")[0]
            if atom.startswith("so:") or atom.startswith("cmd:") or not DEP_ATOM_RE.match(bare):
                raise RepoDbError(
                    f"cannot resolve dependency {atom} of {current} "
                    "for declaration extraction (rebuild and re-publish the package)"
                )
            provider = newest_provider(bare)
            if provider not in closure:
                closure.add(provider)
                queue.append(provider)
    root = work_tmp / "extract-root"
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    copies = work_tmp / "extract-apks"
    copies.mkdir(parents=True, exist_ok=True)
    for filename in sorted(closure):
        shutil.copy2(repo_dir / filename, copies / filename)
    cmd = [apk_bin, "--root", str(root), "--initdb", "--allow-untrusted",
           "--no-scripts", "--no-cache", "--force-non-repository",
           "add", *[str(copies / f) for f in sorted(closure)]]
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        raise RepoDbError(
            "isolated declaration-extraction install failed: "
            + (proc.stderr.strip() or proc.stdout.strip() or str(proc.returncode))
        )
    mk = makepkg()
    decls: dict[str, dict] = {}
    frag_dir = root / FRAGMENT_PREFIX
    for filename in filenames:
        info = cached_dump(filename)
        # Attribute the declaration to the NVR whose file list carries
        # the fragment path (today: the main package). Legacy sidecars
        # (*.legacy) are history, not declarations: the census skips
        # them (their union is checked at publish from staged
        # receipts, and migration preconditions fail closed live).
        frag_files = sorted({f[len(FRAGMENT_PREFIX):] for f in info["files"]
                             if f.startswith(FRAGMENT_PREFIX) and not f.endswith(".legacy")})
        merged = {"users": [], "groups": [], "dirs": [], "files": []}
        for frag in frag_files:
            path = frag_dir / frag
            if not path.is_file():
                raise RepoDbError(
                    f"{filename} lists fragment {frag} but it did not install "
                    "(rebuild and re-publish the package)"
                )
            decl, _notices = mk.parse_accounts_fragment(path)
            for key in ("users", "groups", "dirs", "files"):
                merged[key].extend(decl[key])
        decls[filename] = merged
    return decls


# ---------------------------------------------------------------------------
# row sync
# ---------------------------------------------------------------------------

def sync_packages(conn: sqlite3.Connection, census_data: dict[str, dict],
                  declarations: dict[str, dict], apk_bin: str,
                  published_at: str) -> None:
    """Rebuild packages/files/users/groups/state_dirs from a census.
    Reservations are NOT touched here (see advance_reservations).
    Atomic: one explicit transaction (this connection runs in autocommit
    mode, so without this a kill mid-sync would commit the DELETEs and
    strand a partial INSERT set - exactly the corruption a full audit
    once left behind)."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        _sync_packages_inner(conn, census_data, declarations, apk_bin,
                             published_at)
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    else:
        conn.execute("COMMIT")


def _sync_packages_inner(conn: sqlite3.Connection, census_data: dict[str, dict],
                         declarations: dict[str, dict], apk_bin: str,
                         published_at: str) -> None:
    """Sync body: caller holds the transaction (see sync_packages)."""
    conn.execute("DELETE FROM state_dirs")
    conn.execute("DELETE FROM users")
    conn.execute("DELETE FROM groups")
    conn.execute("DELETE FROM files")
    conn.execute("DELETE FROM packages")
    newest: dict[str, str] = {}
    for filename, info in census_data.items():
        name, version = info["name"], info["version"]
        if name not in newest or apk_newer(apk_bin, version, newest[name]):
            newest[name] = version
    for filename in sorted(census_data):
        info = census_data[filename]
        name, version = info["name"], info["version"]
        conn.execute(
            "INSERT INTO packages(name, version, pkgrel, nvr, apk_sha256, is_newest, published_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (name, version, pkgrel_of(version), f"{name}-{version}",
             info["apk_sha256"], 1 if newest[name] == version else 0, published_at),
        )
        package_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
        conn.executemany("INSERT INTO files(package_id, path) VALUES (?, ?)",
                         [(package_id, p) for p in info["files"]])
        decl = declarations.get(filename, EMPTY_DECL)
        _, decl_sha = canonical_declaration(decl["users"], decl["groups"], decl["dirs"])
        for u in decl["users"]:
            conn.execute(
                "INSERT INTO users(package_id, name, uid, primary_group, home, shell, declaration_sha256)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (package_id, u["name"], int(u["uid"]), u["primary"],
                 u["home"], u["shell"], decl_sha),
            )
        for g in decl["groups"]:
            conn.execute(
                "INSERT INTO groups(package_id, name, gid, declaration_sha256)"
                " VALUES (?, ?, ?, ?)",
                (package_id, g["name"], int(g["gid"]), decl_sha),
            )
        for d in decl["dirs"]:
            conn.execute(
                'INSERT INTO state_dirs(package_id, path, mode, owner, "group")'
                " VALUES (?, ?, ?, ?, ?)",
                (package_id, d["path"], d["mode"], d["owner"], d["group"]),
            )


def active_declarations(conn: sqlite3.Connection) -> list[tuple[str, str, dict]]:
    """Newest-per-package-name declarations (governance view, mirrors the
    old same-name collapse). Returns [(owner_label, package_name,
    declaration)] — the package name travels explicitly so hyphenated
    versions can never corrupt lineage checks."""
    rows = conn.execute(
        "SELECT name, version FROM packages WHERE is_newest=1 ORDER BY name"
    ).fetchall()
    decls: list[tuple[str, str, dict]] = []
    for row in rows:
        package_id = conn.execute(
            "SELECT package_id FROM packages WHERE name=? AND version=?",
            (row["name"], row["version"]),
        ).fetchone()["package_id"]
        users = [dict(r) for r in conn.execute(
            "SELECT name, uid, primary_group AS \"primary\", home, shell FROM users"
            " WHERE package_id=? ORDER BY name", (package_id,)).fetchall()]
        groups = [dict(r) for r in conn.execute(
            "SELECT name, gid FROM groups WHERE package_id=? ORDER BY name",
            (package_id,)).fetchall()]
        dirs = [dict(r) for r in conn.execute(
            'SELECT path, mode, owner, "group" AS "group" FROM state_dirs'
            " WHERE package_id=? ORDER BY path", (package_id,)).fetchall()]
        # Normalize int IDs back to the canonical string form.
        for u in users:
            u["uid"] = str(u["uid"])
        for g in groups:
            g["gid"] = str(g["gid"])
        if users or groups:
            decls.append((f"{row['name']}-{row['version']}", row["name"],
                          {"users": users, "groups": groups, "dirs": dirs}))
    return decls


def advance_reservations(conn: sqlite3.Connection, live: list[tuple[str, str, dict]],
                         from_history: bool, notices: list[str]) -> None:
    """Reconcile the eternal reservation ledger against live (newest)
    declarations. Tombstones are never deleted. Without from_history,
    history is never invented: unknown bindings fail closed."""
    mk = makepkg()
    seen: set[tuple[str, str]] = set()
    for owner, package, decl in live:
        for entry in decl.get("groups", []):
            seen.add(("group", entry["name"]))
            upsert_reservation(conn, "group", entry["name"], int(entry["gid"]),
                               package, owner, decl, notices)
        for entry in decl.get("users", []):
            seen.add(("user", entry["name"]))
            upsert_reservation(conn, "user", entry["name"], int(entry["uid"]),
                               package, owner, decl, notices)
    for row in conn.execute(
            "SELECT kind, name, numeric_id, owning_package, last_nvr FROM reservations"
            " WHERE status='ACTIVE'").fetchall():
        if (row["kind"], row["name"]) not in seen:
            conn.execute(
                "UPDATE reservations SET status='TOMBSTONED' WHERE kind=? AND name=?",
                (row["kind"], row["name"]),
            )
            notices.append(
                f"reservation tombstoned: {row['kind']} {row['name']} "
                f"(was {row['owning_package']} {row['last_nvr']}; IDs never recycle)"
            )
    _ = mk
    _ = from_history


def upsert_reservation(conn: sqlite3.Connection, kind: str, name: str, numeric_id: int,
                       package: str, nvr: str, decl: dict, notices: list[str]) -> None:
    _, decl_sha = canonical_declaration(decl.get("users", []), decl.get("groups", []),
                                        decl.get("dirs", []))
    row = conn.execute(
        "SELECT numeric_id, owning_package, status FROM reservations WHERE kind=? AND name=?",
        (kind, name)).fetchone()
    if row is None:
        clash = conn.execute(
            "SELECT name, owning_package, status FROM reservations"
            " WHERE kind=? AND numeric_id=?", (kind, numeric_id)).fetchone()
        if clash is not None:
            raise RepoDbError(
                f"reservation collision: {kind} {name} ({package} {nvr}) wants "
                f"ID {numeric_id}, already held by {clash['name']} "
                f"({clash['owning_package']}, {clash['status']}); IDs never recycle"
            )
        conn.execute(
            "INSERT INTO reservations(kind, name, numeric_id, owning_package,"
            " first_nvr, last_nvr, status, declaration_sha256)"
            " VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE', ?)",
            (kind, name, numeric_id, package, nvr, nvr, decl_sha),
        )
        return
    if row["numeric_id"] != numeric_id or row["owning_package"] != package:
        raise RepoDbError(
            f"reservation mismatch: {kind} {name} historically "
            f"{row['owning_package']} ID {row['numeric_id']} ({row['status']}), "
            f"now {package} ID {numeric_id} in {nvr}"
        )
    conn.execute(
        "UPDATE reservations SET status='ACTIVE', last_nvr=?, declaration_sha256=?"
        " WHERE kind=? AND name=?",
        (nvr, decl_sha, kind, name),
    )


# ---------------------------------------------------------------------------
# fast-path freshness + gate queries
# ---------------------------------------------------------------------------

def index_identities(apk_bin: str, index_path: str | Path) -> set[tuple[str, str]]:
    dump = subprocess.run(
        [apk_bin, "adbdump", str(index_path)],
        check=True, text=True, capture_output=True,
    ).stdout
    names = re.findall(r"^  - name: (\S+)$", dump, re.MULTILINE)
    versions = re.findall(r"^    version: (\S+)$", dump, re.MULTILINE)
    if len(names) != len(versions):
        raise RepoDbError(f"malformed repository index identities: {index_path}")
    return set(zip(names, versions))


def disk_set(repo_dir: str | Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in Path(repo_dir).glob("*.apk"):
        if path.is_file() and not path.is_symlink():
            result[path.name] = sha256_file(path)
    return result


def freshness(conn: sqlite3.Connection, apk_bin: str, repo_dir: str | Path,
              index_path: str | Path, trust_dir: str | Path) -> tuple[bool, str]:
    """Fast freshness: index signature (one op) + index identities vs DB +
    disk filename/sha set vs DB. No per-package dump. Returns (fresh, reason)."""
    try:
        subprocess.run([apk_bin, "verify", "--keys-dir", str(trust_dir), str(index_path)],
                       check=True, capture_output=True, text=True)
        idx = index_identities(apk_bin, index_path)
    except (subprocess.CalledProcessError, RepoDbError) as exc:
        return False, f"index unreadable: {exc}"
    db_idents = {(r["name"], r["version"]) for r in
                 conn.execute("SELECT name, version FROM packages").fetchall()}
    if idx != db_idents:
        return False, (f"index holds {len(idx)} APK identities,"
                       f" database {len(db_idents)}")
    disk = disk_set(repo_dir)
    db_files = {f"{r['name']}-{r['version']}.apk": r["apk_sha256"] for r in
                conn.execute("SELECT name, version, apk_sha256 FROM packages").fetchall()}
    if set(disk) != set(db_files):
        return False, "repository APK set does not match database"
    for filename, digest in disk.items():
        if digest != db_files[filename]:
            return False, f"content changed under immutable NVR: {filename}"
    return True, f"{len(db_idents)} APK identities"


def newest_owners(conn: sqlite3.Connection) -> dict[str, dict[str, str]]:
    """{path: {package_name: nvr}} for newest-per-name packages (governance
    view, mirrors the old owners map)."""
    owners: dict[str, dict[str, str]] = {}
    for row in conn.execute(
            "SELECT package_id, name, version FROM packages WHERE is_newest=1").fetchall():
        nvr = f"{row['name']}-{row['version']}"
        for frow in conn.execute("SELECT path FROM files WHERE package_id=?",
                                 (row["package_id"],)).fetchall():
            owners.setdefault(frow["path"], {})[row["name"]] = nvr
    return owners


# ---------------------------------------------------------------------------
# TSV base-seed authority (tiny file, re-read every run, never cached)
# ---------------------------------------------------------------------------

def parse_tsv(path: str | Path) -> tuple[dict[str, int], dict[str, int]] | None:
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return None
    users: dict[str, int] = {}
    groups: dict[str, int] = {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 3:
            raise RepoDbError(f"malformed accounts.tsv line {lineno}")
        name, kind, ident = fields[0], fields[1], fields[2]
        if kind == "user":
            users[name] = int(ident)
        elif kind == "group":
            groups[name] = int(ident)
        else:
            raise RepoDbError(f"malformed accounts.tsv line {lineno}: {kind}")
    return users, groups


# ---------------------------------------------------------------------------
# owner/gate evaluation shared by the signer (single implementation)
# ---------------------------------------------------------------------------

# Init-system selector co-ownership (Saphira duality invariant: either
# init installs without recompiling, swapped del-then-add). PID 1's
# canonical path cannot move to /usr/sbin the way systemd's
# halt/poweroff/reboot/shutdown siblings did, so exactly this one path
# is deliberately co-owned by exactly these two packages. See
# gate_staged for the enforcement and its limits.
SHARED_INIT_SELECTOR = "sbin/init"
SHARED_INIT_OWNERS = frozenset({"systemd", "openrc"})


def evaluate_file_collisions(owners: dict[str, dict[str, str]],
                             staged_identities: set[tuple[str, str]],
                             staged_paths: dict[tuple[str, str], set[str]],
                             staged_replaces: dict[tuple[str, str], set[str]]) -> dict[str, tuple[str, str]]:
    collisions: dict[str, tuple[str, str]] = {}
    for path, name_versions in sorted(owners.items()):
        if len(name_versions) < 2:
            continue
        names = set(name_versions)
        staged_here = sorted(ident for ident in staged_identities if path in staged_paths[ident])
        if not staged_here:
            continue
        for staged_identity in staged_here:
            staged_name = staged_identity[0]
            others = names - {staged_name}
            if not others:
                continue
            if others <= staged_replaces.get(staged_identity, set()):
                continue
            detail = ", ".join(name_versions[n] for n in sorted(others))
            collisions[path] = (name_versions[staged_name], detail)
    return collisions


# ---------------------------------------------------------------------------
# Hatched retention: keep latest N per name, hold live deps + explicit holds
# ---------------------------------------------------------------------------
# The live generation keeps the newest KEEP NVRs per package name. Older
# NVRs retire unless a live dependent needs exactly them (a constraint no
# kept NVR satisfies) or they sit on the explicit hold list. Retirement
# always happens inside the signer's publication transaction (files go
# before index regen, rows go with the staged apply) - never bare rm.
# Archive generations are never pruned.

DEPEND_ATOM_RE = re.compile(
    r"^([A-Za-z0-9][A-Za-z0-9._+-]*?)((>=|<=|=|>|<|~)(.+))?$")

_compare_cache: dict[tuple[str, str, str], str] = {}


def apk_cmp(apk_bin: str, a: str, b: str) -> str:
    """apk version comparison with memoization: '<', '=' or '>'."""
    key = (apk_bin, a, b)
    result = _compare_cache.get(key)
    if result is None:
        out = subprocess.run([apk_bin, "version", "-t", a, b], check=True,
                             text=True, capture_output=True).stdout.strip()
        result = out if out in ("<", "=", ">") else "="
        _compare_cache[key] = result
    return result


def apk_versions_desc(apk_bin: str, versions) -> list:
    """Newest-first ordering via apk semantics (duplicates collapsed)."""
    import functools

    def compare(a, b):
        result = apk_cmp(apk_bin, a, b)
        return 1 if result == "<" else (-1 if result == ">" else 0)

    return sorted(set(versions), key=functools.cmp_to_key(compare))


def _base_of(version: str) -> str:
    match = VERSION_BASE_RE.fullmatch(version)
    return match.group("base") if match else version


def depend_satisfied(apk_bin: str, atom: str, kept_versions) -> bool:
    """Whether any kept version satisfies one dependency atom. Opaque
    atoms (so:, /path, virtuals) never satisfy by themselves: holds form
    only on positively provable edges."""
    match = DEPEND_ATOM_RE.fullmatch(atom)
    if not match or "/" in atom or ":" in atom:
        return False
    op, want = match.group(3), match.group(4)
    if op is None or op == "~":
        return bool(kept_versions)
    if op == "=" and VERSION_BASE_RE.fullmatch(want) is None:
        return any(apk_cmp(apk_bin, _base_of(v), _base_of(want)) == "="
                   for v in kept_versions)
    if op == "=":
        return want in kept_versions
    if op == ">=":
        return any(apk_cmp(apk_bin, v, want) in ("=", ">") for v in kept_versions)
    if op == ">":
        return any(apk_cmp(apk_bin, v, want) == ">" for v in kept_versions)
    if op == "<=":
        return any(apk_cmp(apk_bin, v, want) in ("=", "<") for v in kept_versions)
    if op == "<":
        return any(apk_cmp(apk_bin, v, want) == "<" for v in kept_versions)
    return False


def index_depends(apk_bin: str, index_path) -> dict:
    """{(name, version): [depends]} from one ADB index dump."""
    try:
        dump = subprocess.run([apk_bin, "adbdump", str(index_path)], check=True,
                              text=True, capture_output=True).stdout
    except subprocess.CalledProcessError as exc:
        raise RepoDbError(f"cannot dump index {index_path}: exit {exc.returncode}:"
                          f" {(exc.stderr or '').strip()[:300]}")
    result: dict[tuple[str, str], list[str]] = {}
    name = version = None
    depends: list[str] | None = None
    in_depends = False
    for line in dump.splitlines():
        match = re.match(r"^  - name: (\S+)$", line)
        if match:
            if name is not None and version is not None:
                result[(name, version)] = depends or []
            name, version, depends, in_depends = match.group(1), None, None, False
            continue
        match = re.match(r"^    version: (\S+)$", line)
        if match and name is not None:
            version = match.group(1)
            continue
        if re.match(r"^    depends:", line):
            depends, in_depends = [], True
            continue
        if line.startswith("      - ") and in_depends and depends is not None:
            depends.append(line[len("      - "):].strip())
            continue
        if re.match(r"^    \S", line):
            in_depends = False
    if name is not None and version is not None:
        result[(name, version)] = depends or []
    return result


def _live_needs_version(apk_bin: str, name: str, version: str, live: set,
                        staged: dict, index_depends_map: dict,
                        kept_versions: dict) -> tuple[str, str] | None:
    """(dependent NVR, edge) if a live dependent needs exactly this
    published version (no kept version satisfies the edge), else None."""
    for dep_name, dep_version in sorted(live):
        if dep_name == name:
            continue
        edges = staged.get((dep_name, dep_version))
        if edges is None:
            edges = index_depends_map.get((dep_name, dep_version), [])
        for edge in edges:
            match = DEPEND_ATOM_RE.fullmatch(edge)
            if not match or "/" in edge or ":" in edge:
                continue
            if match.group(1) != name:
                continue
            if (not depend_satisfied(apk_bin, edge, kept_versions.get(name, []))
                    and depend_satisfied(apk_bin, edge, [version])):
                return (f"{dep_name}-{dep_version}", edge)
    return None


def compute_retire_set(conn, apk_bin: str, staged: dict,
                       index_depends_map: dict, keep: int,
                       holds) -> set:
    """Filenames ('nvr.apk') to retire from the live generation. staged maps
    (name, version) to depends lists; index_depends_map covers published
    newest packages the same way. keep<1 is refused. Never returns staged
    or explicitly held NVRs. Prune order: (1) every published r0 retires
    unconditionally - r0 is inadmissible in the live view, never a
    retention/rollback candidate, never held, never a satisfier; (2)
    normal retention over r1+ (latest keep generations, exact live
    dependency holds, explicit holds); (3) split siblings retire together
    in the caller's single pass. An explicit hold naming an r0, or a live
    dependent needing an r0, fails closed."""
    if keep < 1:
        raise RepoDbError(f"retention keep must be >= 1: {keep}")
    holds_norm = set()
    for hold in holds or []:
        hold = hold.strip()
        if hold.endswith(".apk"):
            hold = hold[:-4]
        if hold:
            holds_norm.add(hold)
    published: dict[str, list] = {}
    for row in conn.execute("SELECT name, version FROM packages"):
        published.setdefault(row["name"], []).append(row["version"])
    staged_idents = set(staged)
    # Step 1 - r0 purge. pkgrel is lineage-local: this is a flat
    # pkgrel == 0 filter, never a cross-lineage version comparison.
    r0_idents = {(name, version)
                 for name, versions in published.items()
                 for version in versions
                 if pkgrel_of(version) == 0} - staged_idents
    for (name, version) in sorted(r0_idents):
        if f"{name}-{version}" in holds_norm:
            raise RepoDbError(
                f"explicit retention hold on r0 is rejected: {name}-{version}"
                " (r0 is inadmissible in the live view; holds only ever pin r1+)")
    post_newest: dict[str, str] = {}
    kept_versions: dict[str, list] = {}
    for name in sorted(set(published) | {n for n, _v in staged}):
        versions = list(published.get(name, []))
        for n, v in staged:
            if n == name and v not in versions:
                versions.append(v)
        ranked = apk_versions_desc(apk_bin, versions)
        if ranked:
            post_newest[name] = ranked[0]
        # r0 is never a retention candidate and never satisfies a live
        # edge: a dependent "satisfied" only by an r0 is broken, and the
        # r0 pass above (gate first, then prune) says so loudly.
        kept_versions[name] = [v for v in ranked[:keep] if pkgrel_of(v) != 0]
    live = ((set(staged) | {(n, post_newest[n]) for n in post_newest})
            - r0_idents)
    retired = set()
    for (name, version) in sorted(r0_idents):
        need = _live_needs_version(apk_bin, name, version, live, staged,
                                   index_depends_map, kept_versions)
        if need is not None:
            dependent, edge = need
            raise RepoDbError(
                f"live package {dependent} depends on '{edge}', satisfiable"
                f" only by r0 {name}-{version} (broken live dependency: r0 is"
                " inadmissible in the live view and is never retained to"
                " satisfy it - fix the consumer recipe at r1+)")
        retired.add(f"{name}-{version}.apk")
    for name in sorted(set(published) | {n for n, _v in staged}):
        versions = list(published.get(name, []))
        for n, v in staged:
            if n == name and v not in versions:
                versions.append(v)
        ranked = apk_versions_desc(apk_bin, versions)
        for version in ranked[keep:]:
            ident = (name, version)
            if ident in staged:
                continue
            if pkgrel_of(version) == 0:
                continue  # step 1 above owns every published r0
            nvr = f"{name}-{version}"
            if nvr in holds_norm:
                continue
            if _live_needs_version(apk_bin, name, version, live, staged,
                                   index_depends_map, kept_versions) is None:
                retired.add(f"{nvr}.apk")
    return retired


def apply_retire(conn, apk_bin: str, filenames, touched=frozenset(),
               notices=None) -> None:
    """Delete retired NVRs (rows only; the caller removed the APK files
    before index regen). Refuses newest rows - except r0, which is
    inadmissible in the live view and retires even when newest (an
    r0-only package goes absent rather than retained). When an r0-newest
    retires over surviving older rows, the best admissible survivor is
    crowned newest so its claims stay live, and its declarations become
    the ACTIVE reservations. Names applied in the same transaction were
    already reconciled by apply_staged and are left alone; other retired
    names tombstone the ACTIVE reservations orphaned here (IDs never
    recycle). The caller holds the transaction."""
    if notices is None:
        notices = []
    retired_names: set[str] = set()
    for filename in sorted(filenames):
        nvr = filename[:-4] if filename.endswith(".apk") else filename
        row = conn.execute(
            "SELECT package_id, name, version, is_newest FROM packages WHERE nvr=?",
            (nvr,)).fetchone()
        if row is None:
            raise RepoDbError(f"retire set references missing package: {filename}")
        if row["is_newest"] and pkgrel_of(row["version"]) != 0:
            raise RepoDbError(f"refusing to retire newest package: {filename}")
        package_id = row["package_id"]
        conn.execute("DELETE FROM state_dirs WHERE package_id=?", (package_id,))
        conn.execute("DELETE FROM users WHERE package_id=?", (package_id,))
        conn.execute("DELETE FROM groups WHERE package_id=?", (package_id,))
        conn.execute("DELETE FROM files WHERE package_id=?", (package_id,))
        conn.execute("DELETE FROM packages WHERE package_id=?", (package_id,))
        retired_names.add(row["name"])
    for name in sorted(retired_names):
        if name in touched:
            continue  # apply_staged already reconciled this lineage
        survivors = [r["version"] for r in conn.execute(
            "SELECT version FROM packages WHERE name=?", (name,)).fetchall()]
        if not survivors:
            # Lineage going absent: its ACTIVE reservations die with it
            # (tombstoned, never deleted - IDs never recycle).
            for res in conn.execute(
                    "SELECT kind, name, last_nvr FROM reservations"
                    " WHERE owning_package=? AND status='ACTIVE'",
                    (name,)).fetchall():
                conn.execute(
                    "UPDATE reservations SET status='TOMBSTONED' WHERE kind=? AND name=?",
                    (res["kind"], res["name"]))
                notices.append(
                    f"reservation tombstoned: {res['kind']} {res['name']}"
                    f" ({res['last_nvr']} retired from live; IDs never recycle)")
            continue
        if conn.execute("SELECT COUNT(*) c FROM packages WHERE name=? AND is_newest=1",
                        (name,)).fetchone()["c"]:
            continue
        # An r0-newest retired over older survivors: crown the best
        # admissible (non-r0) survivor so its claims stay live.
        admissible = [v for v in survivors if pkgrel_of(v) != 0]
        best = apk_versions_desc(apk_bin, admissible or survivors)[0]
        conn.execute("UPDATE packages SET is_newest=1 WHERE name=? AND version=?",
                     (name, best))
        notices.append(
            f"{name}: newest recomputed as {name}-{best} (r0 retired from live)")
        crowned_id = conn.execute(
            "SELECT package_id FROM packages WHERE name=? AND version=?",
            (name, best)).fetchone()["package_id"]
        users = [dict(r) for r in conn.execute(
            'SELECT name, uid, primary_group AS "primary", home, shell FROM users'
            " WHERE package_id=? ORDER BY name", (crowned_id,)).fetchall()]
        groups = [dict(r) for r in conn.execute(
            "SELECT name, gid FROM groups WHERE package_id=? ORDER BY name",
            (crowned_id,)).fetchall()]
        for u in users:
            u["uid"] = str(u["uid"])
        for g in groups:
            g["gid"] = str(g["gid"])
        decl = {"users": users, "groups": groups, "dirs": []}
        for entry in groups:
            upsert_reservation(conn, "group", entry["name"], int(entry["gid"]),
                               name, f"{name}-{best}", decl, notices)
        for entry in users:
            upsert_reservation(conn, "user", entry["name"], int(entry["uid"]),
                               name, f"{name}-{best}", decl, notices)
        live_users = {entry["name"] for entry in users}
        live_groups = {entry["name"] for entry in groups}
        for kind, sub in (("user", live_users), ("group", live_groups)):
            for res in conn.execute(
                    "SELECT name, last_nvr FROM reservations"
                    " WHERE kind=? AND owning_package=? AND status='ACTIVE'",
                    (kind, name)).fetchall():
                if res["name"] not in sub:
                    conn.execute(
                        "UPDATE reservations SET status='TOMBSTONED', last_nvr=?"
                        " WHERE kind=? AND name=?",
                        (f"{name}-{best}", kind, res["name"]))
                    notices.append(
                        f"reservation tombstoned: {kind} {res['name']}"
                        f" (dropped by {name}-{best}; IDs never recycle)")


def check_union(tsv_users: dict[str, int], tsv_groups: dict[str, int],
                decls: list[tuple[str, dict]]) -> None:
    """Exactly one package owns each declared Unix identity. The TSV base
    seed is NOT the authority: identical redeclaration converges, differing
    attributes collide. IDs outside 0..887 refuse. Mirrors the JSON-era
    account gate rule-for-rule."""
    mk = makepkg()
    max_id = mk.MAX_PACKAGED_ID
    reserved_users = mk.RESERVED_USER_NAMES
    reserved_groups = mk.RESERVED_GROUP_NAMES
    reserved_gids = mk.RESERVED_GIDS
    users: dict[str, tuple[str, int]] = {}
    uids: dict[int, tuple[str, str]] = {}
    groups: dict[str, tuple[str, int]] = {}
    gids: dict[int, tuple[str, str]] = {}
    errors: list[str] = []
    for owner, decl in decls:
        for entry in decl.get("groups", []):
            name, gid = entry["name"], int(entry["gid"])
            if name in reserved_groups or gid in reserved_gids:
                errors.append(f"group {name}: {owner} declares reserved foundation identity")
            elif gid > max_id:
                errors.append(f"group {name}: {owner} GID {gid} is outside the packaged range 0..{max_id}")
            elif name in tsv_groups:
                if tsv_groups[name] != gid:
                    errors.append(f"group {name}: {owner} GID {gid} conflicts with base seed GID {tsv_groups[name]}")
            elif name in groups:
                errors.append(f"group {name}: claimed by {groups[name][0]} and {owner}")
            elif gid in tsv_groups.values():
                clash = sorted(n for n, g in tsv_groups.items() if g == gid)[0]
                errors.append(f"GID {gid}: {owner} group {name} collides with base seed {clash}")
            elif gid in gids:
                errors.append(f"GID {gid}: {owner} group {name} collides with {gids[gid][0]} group {gids[gid][1]}")
            else:
                groups[name] = (owner, gid)
                gids[gid] = (owner, name)
        own_groups = {entry["name"] for entry in decl.get("groups", [])}
        for entry in decl.get("users", []):
            name = entry["name"]
            uid = int(entry["uid"])
            primary = entry["primary"]
            if name in reserved_users or uid == 0:
                errors.append(f"user {name}: {owner} declares reserved system identity")
            elif primary in reserved_groups:
                errors.append(f"user {name}: {owner} primary group {primary} is a reserved foundation group")
            elif uid > max_id:
                errors.append(f"user {name}: {owner} UID {uid} is outside the packaged range 0..{max_id}")
            elif name in tsv_users:
                if tsv_users[name] != uid:
                    errors.append(f"user {name}: {owner} UID {uid} conflicts with base seed UID {tsv_users[name]}")
                elif primary not in tsv_groups and primary not in own_groups:
                    errors.append(f"user {name}: {owner} primary group {primary} is neither base-seeded nor declared in the same fragment")
            elif name in users:
                errors.append(f"user {name}: claimed by {users[name][0]} and {owner}")
            elif uid in tsv_users.values():
                clash = sorted(n for n, u in tsv_users.items() if u == uid)[0]
                errors.append(f"UID {uid}: {owner} user {name} collides with base seed {clash}")
            elif uid in uids:
                errors.append(f"UID {uid}: {owner} user {name} collides with {uids[uid][0]} user {uids[uid][1]}")
            elif primary not in tsv_groups and primary not in own_groups:
                errors.append(f"user {name}: {owner} primary group {primary} is neither base-seeded nor declared in the same fragment")
            else:
                users[name] = (owner, uid)
                uids[uid] = (owner, name)
    if errors:
        raise RepoDbError(
            "account identity collision - one package owns each declared Unix identity:\n  "
            + "\n  ".join(sorted(errors))
        )

def check_legacy_union(staged_info: dict, combined_decls: list[tuple[str, dict]]) -> None:
    """Legacy history must never collide with any present identity.

    A legacy UID/GID claimed as history while declared (active or
    staged, by any package) makes migration targets ambiguous; legacy
    history claimed twice is incoherent (one past, one owner). Refuse
    naming the collision. Published sidecars are not parsed here
    (census reads declarations only); migration-time preconditions
    fail closed on any residual overlap, so gate plus command cover
    both layers.

    Namespace split: a legacy user's UID claims user-namespace
    history; a legacy group's GID claims group-namespace history. A
    legacy user's primary GID is a reference, not a claim - the
    universal paired shape (user foo N + group foo N), shared
    primaries, and unchanged primaries must not self-collide - so it
    is checked against neither declared groups nor other history.
    Group-namespace coverage comes from the legacy group entries,
    which makepkg requires to name groups the same fragment declares.
    """
    uids: dict[int, str] = {}
    gids: dict[int, str] = {}
    for owner, decl in combined_decls:
        for entry in decl.get("users", []):
            uids.setdefault(int(entry["uid"]), owner)
        for entry in decl.get("groups", []):
            gids.setdefault(int(entry["gid"]), owner)
    seen_uids: dict[int, str] = {}
    seen_gids: dict[int, str] = {}
    errors: list[str] = []
    for name in sorted(staged_info):
        label = f"staged:{name}"
        legacy = staged_info[name].get("accounts", {}).get("legacy", {"users": [], "groups": []})
        for entry in legacy.get("users", []):
            uid = int(entry["uid"])
            if uid in uids:
                errors.append(f"legacy user {entry['name']}: {label} old UID {uid} collides with {uids[uid]}")
            elif uid in seen_uids:
                errors.append(f"legacy user {entry['name']}: {label} old UID {uid} already claimed as history by {seen_uids[uid]}")
            else:
                seen_uids[uid] = label
        for entry in legacy.get("groups", []):
            gid = int(entry["gid"])
            if gid in gids:
                errors.append(f"legacy group {entry['name']}: {label} old GID {gid} collides with {gids[gid]}")
            elif gid in seen_gids:
                errors.append(f"legacy group {entry['name']}: {label} old GID {gid} already claimed as history by {seen_gids[gid]}")
            else:
                seen_gids[gid] = label
    if errors:
        raise RepoDbError(
            "legacy history collides with declared identities:\n  "
            + "\n  ".join(sorted(errors))
        )


def check_file_references(label: str, accounts: dict) -> None:
    """File-stanza references resolve to what the package owns plus root.

    A file stanza never declares an identity: its owner/group must be a
    user/group declared in the same fragment, or the root/0 built-in
    (which needs no declaration). Anything else is a typo or a
    cross-package ownership grab, and publication fails closed naming
    it. The live reconciler re-checks resolution independently.
    """
    own_users = {entry["name"] for entry in accounts.get("users", [])}
    own_groups = {entry["name"] for entry in accounts.get("groups", [])}
    errors: list[str] = []
    for entry in accounts.get("files", []):
        if entry["owner"] not in own_users and entry["owner"] not in ("root", "0"):
            errors.append(
                f"file {entry['path']}: {label} owner '{entry['owner']}' is neither declared by this package nor the root built-in")
        if entry["group"] not in own_groups and entry["group"] not in ("root", "0"):
            errors.append(
                f"file {entry['path']}: {label} group '{entry['group']}' is neither declared by this package nor the root built-in")
    if errors:
        raise RepoDbError(
            "file ownership references undeclared identities:\n  "
            + "\n  ".join(sorted(errors))
        )

def check_reservations(conn: sqlite3.Connection,
                       staged: list[tuple[str, str, dict]]) -> None:
    """Eternal ledger enforcement for the staged set: a staged declaration
    touching a TOMBSTONED binding is refused unless it is the same package
    lineage reclaiming its canonical ID."""
    for owner, package, decl in staged:
        for entry in decl.get("groups", []):
            reservation_hit(conn, "group", entry["name"], int(entry["gid"]), package, owner)
        for entry in decl.get("users", []):
            reservation_hit(conn, "user", entry["name"], int(entry["uid"]), package, owner)


def reservation_hit(conn: sqlite3.Connection, kind: str, name: str, numeric_id: int,
                    package: str, owner: str) -> None:
    row = conn.execute(
        "SELECT numeric_id, owning_package, status FROM reservations"
        " WHERE kind=? AND (name=? OR numeric_id=?)", (kind, name, numeric_id)).fetchone()
    # Exact-name row governs first.
    own = conn.execute(
        "SELECT numeric_id, owning_package, status FROM reservations WHERE kind=? AND name=?",
        (kind, name)).fetchone()
    if own is not None:
        if own["numeric_id"] == numeric_id and own["owning_package"] == package:
            return  # live binding or legitimate same-lineage reclaim
        raise RepoDbError(
            f"reservation refusal: {kind} {name} ({owner}) conflicts with "
            f"{own['status']} reservation ({own['owning_package']} ID {own['numeric_id']})"
        )
    if row is not None:
        raise RepoDbError(
            f"reservation refusal: {kind} {name} ({owner}) wants ID {numeric_id}, "
            f"held by {row['status']} reservation {row['owning_package']}; IDs never recycle"
        )


# ---------------------------------------------------------------------------
# writer lock: every sanctioned writer takes the same per-repo lock before
# opening the database read-write. mkdir is atomic; failure means another
# writer holds it (fail closed, never wait silently).
# ---------------------------------------------------------------------------

def db_lock_path(repo_dir: str | Path) -> Path:
    return Path(repo_dir) / "repository.db.lock"


def acquire_db_lock(repo_dir: str | Path) -> Path:
    lock = db_lock_path(repo_dir)
    try:
        os.mkdir(lock)
    except FileExistsError:
        raise RepoDbError(f"repository writer lock already held: {lock}")
    return lock


def release_db_lock(repo_dir: str | Path) -> None:
    lock = db_lock_path(repo_dir)
    try:
        os.rmdir(lock)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# history ledger derivation (complete-history censuses only: migration,
# --reconcile --from-history, full audit on the append-only archive)
# ---------------------------------------------------------------------------

def _ordered_versions(apk_bin: str, versions: list[str]) -> list[str]:
    def cmp(a: str, b: str) -> int:
        if apk_newer(apk_bin, a, b):
            return 1
        if apk_newer(apk_bin, b, a):
            return -1
        return 0

    return sorted(versions, key=cmp_to_key(cmp))


def derive_ledger(apk_bin: str, census_data: dict, declarations: dict,
                  notices: list[str]) -> list[tuple]:
    """Walk every package name oldest-to-newest; bindings that vanish in a
    later version tombstone (IDs never recycle). Returns reservation rows."""
    by_name: dict[str, list[str]] = {}
    for _filename, info in census_data.items():
        by_name.setdefault(info["name"], []).append(info["version"])
    rows: list[tuple] = []
    for name in sorted(by_name):
        bindings: dict[tuple[str, str], list] = {}
        for version in _ordered_versions(apk_bin, by_name[name]):
            filename = f"{name}-{version}.apk"
            decl = declarations.get(filename, {"users": [], "groups": [], "dirs": [], "files": []})
            owner = f"{name}-{version}"
            for entry in decl.get("groups", []):
                key = ("group", entry["name"])
                cell = [entry["name"], int(entry["gid"]), owner, decl]
                if key not in bindings:
                    bindings[key] = [owner, owner, cell]
                else:
                    first, _, old = bindings[key]
                    if old[1] != cell[1]:
                        raise RepoDbError(
                            f"history inconsistent: group {entry['name']} was GID "
                            f"{old[1]} then GID {cell[1]} ({owner})"
                        )
                    bindings[key][1] = owner
            for entry in decl.get("users", []):
                key = ("user", entry["name"])
                cell = [entry["name"], int(entry["uid"]), owner, decl]
                if key not in bindings:
                    bindings[key] = [owner, owner, cell]
                else:
                    first, _, old = bindings[key]
                    if old[1] != cell[1]:
                        raise RepoDbError(
                            f"history inconsistent: user {entry['name']} was UID "
                            f"{old[1]} then UID {cell[1]} ({owner})"
                        )
                    bindings[key][1] = owner
        newest = _ordered_versions(apk_bin, by_name[name])[-1]
        newest_decl = declarations.get(f"{name}-{newest}.apk",
                                       {"users": [], "groups": [], "dirs": []})
        live = {("group", e["name"]) for e in newest_decl.get("groups", [])}
        live |= {("user", e["name"]) for e in newest_decl.get("users", [])}
        for (kind, _), (first, last, cell) in sorted(bindings.items()):
            _, decl_sha = canonical_declaration(
                cell[3].get("users", []), cell[3].get("groups", []), cell[3].get("dirs", []))
            status = "ACTIVE" if (kind, cell[0]) in live else "TOMBSTONED"
            if status == "TOMBSTONED":
                notices.append(
                    f"reservation tombstoned from history: {kind} {cell[0]} "
                    f"(last {last}; IDs never recycle)"
                )
            rows.append((kind, cell[0], cell[1], name, first, last, status, decl_sha))
    return rows


# ---------------------------------------------------------------------------
# staged-set evaluation (identical in fast and full modes)
# ---------------------------------------------------------------------------

def gate_staged(conn: sqlite3.Connection, apk_bin: str, staged_accounts_path: str | Path,
                staged_filenames: set[str], package_paths: list[str],
                tsv_path: str | Path) -> tuple[dict, list[str]]:
    """Evaluate the staged set against the ledger. Returns (staged_info,
    notices). Raises RepoDbError on any refusal. staged_info maps filename
    to {name, version, files, replaces, accounts} for the publication
    transaction."""
    with open(staged_accounts_path, encoding="utf-8") as stream:
        staged_receipts = json.load(stream)
    info: dict[str, dict] = {}
    seen: set[tuple[str, str]] = set()
    staged_identities: set[tuple[str, str]] = set()
    staged_paths: dict[tuple[str, str], set[str]] = {}
    staged_replaces: dict[tuple[str, str], set[str]] = {}
    staged_depends: dict[tuple[str, str], list[str]] = {}
    staged_decl_list: list[tuple[str, str, dict]] = []
    from collections import defaultdict

    staged_paths_dd: dict[tuple[str, str], set[str]] = defaultdict(set)
    for raw in package_paths:
        package = Path(raw)
        dumped = dump_package(apk_bin, package)
        identity = (dumped["name"], dumped["version"])
        if package.name != f"{identity[0]}-{identity[1]}.apk":
            raise RepoDbError(f"package filename does not match identity: {package}")
        if identity in seen:
            raise RepoDbError(f"duplicate package identity: {identity[0]}={identity[1]}")
        seen.add(identity)
        if package.name in staged_filenames:
            staged_identities.add(identity)
            staged_replaces[identity] = set(dumped["replaces"])
            staged_depends[identity] = list(dumped["depends"])
            staged_paths_dd[identity].update(dumped["files"])
            item = staged_receipts.get(package.name,
                                       {"accounts": {"users": [], "groups": [], "dirs": [], "files": []}})
            accounts = item["accounts"]
            declared = bool(accounts.get("users") or accounts.get("groups") or accounts.get("files"))
            fragment_here = any(f.startswith(FRAGMENT_PREFIX) for f in dumped["files"])
            if fragment_here and not declared:
                raise RepoDbError(
                    f"{package.name} ships an accounts.d fragment but its build "
                    "receipt declares nothing (build chain integrity failure)")
            if declared and not fragment_here:
                raise RepoDbError(
                    f"{package.name} receipt declares Unix identities but ships no "
                    "accounts.d fragment (build chain integrity failure)")
            staged_decl_list.append((f"staged:{identity[0]}-{identity[1]}",
                                       identity[0], accounts))
            info[package.name] = {"name": identity[0], "version": identity[1],
                                  "files": sorted(dumped["files"]),
                                  "replaces": sorted(dumped["replaces"]),
                                  "accounts": accounts}
    staged_paths = dict(staged_paths_dd)
    # Merge staged files into the working owners map (newer-or-novel
    # only, mirroring newest collapse): without this, two NEW packages
    # colliding on a path neither owns yet would escape the gate.
    owners = newest_owners(conn)
    newest = {r["name"]: r["version"] for r in conn.execute(
        "SELECT name, version FROM packages WHERE is_newest=1").fetchall()}
    # r0 is inadmissible in the live view: published r0 claims are
    # history, never active claims. A historical r0 still physically
    # present (archive generation, or live awaiting its retirement
    # transaction) must not block a legitimate successor or sibling
    # split the way an active r1+ claim does. pkgrel is lineage-local
    # (no generic "any r1 beats every r0" comparison across unrelated
    # pkgvers): the rule is a flat admissibility filter on pkgrel == 0,
    # applied to published claims only. Staged packages always
    # participate fully, so single-generation archive runs still gate
    # staged r0 fixtures against each other.
    staged_names = {name for (name, _version) in staged_identities}
    r0_names = {name for name, version in newest.items()
                if pkgrel_of(version) == 0} - staged_names
    if r0_names:
        for path, name_versions in list(owners.items()):
            for name in [candidate for candidate in name_versions
                         if candidate in r0_names]:
                del name_versions[name]
            if not name_versions:
                del owners[path]
    for ident in sorted(staged_identities):
        name, version = ident
        current = newest.get(name)
        if current is None or apk_newer(apk_bin, version, current):
            for path in staged_paths[ident]:
                owners.setdefault(path, {})[name] = f"{name}-{version}"
            # Newer-or-novel abandonment: a staged successor retires its own
            # published claims on paths it no longer ships (subpackage file
            # moves, dropped payloads). Without this, a file moving from a
            # package to a sibling subpackage (or any takeover of an
            # abandoned path) could never publish: the stale published claim
            # would collide forever. True conflicts are unaffected: a path
            # the staged successor still ships keeps its claim below.
            for path, name_versions in list(owners.items()):
                if (name in name_versions
                        and name_versions[name] == f"{name}-{current}"
                        and path not in staged_paths[ident]):
                    del name_versions[name]
                    if not name_versions:
                        del owners[path]
    collisions = evaluate_file_collisions(owners, staged_identities,
                                          staged_paths, staged_replaces)
    # Shared init selector: admit sbin/init co-owned by exactly the two
    # init systems, and nothing else. Swapping inits is del-then-add -
    # apk never overwrites a live-owned file, so no --force-overwrite
    # exists anywhere in that flow; only the repository may hold both
    # selectors at once. A third claimant on this path, or any other
    # shared path, still fails closed below. Install-time behavior is
    # untouched: adding an init while the other is installed refuses.
    shared_init: dict[str, list[str]] = {
        path: sorted(owners.get(path, {}))
        for path in collisions
        if path == SHARED_INIT_SELECTOR
        and set(owners.get(path, {}))
        and set(owners.get(path, {})) <= SHARED_INIT_OWNERS
        and {ident[0] for ident in staged_identities
             if path in staged_paths.get(ident, ())} <= SHARED_INIT_OWNERS
    }
    for path in shared_init:
        del collisions[path]
    if collisions:
        lines = [f"{path}: claimed by {sv} and {dv}" for path, (sv, dv) in sorted(collisions.items())]
        raise RepoDbError(
            "file ownership collision - exactly one package must own a path; "
            "fix the recipe split (never --force-overwrite):\n  " + "\n  ".join(lines)
        )
    # A staged package that exactly pins an r0 NVR is a broken live
    # dependency: r0 is inadmissible in the live view and is never
    # retained to satisfy anything, so publication fails closed here
    # naming the broken dependent. Only exact (=) pins on an r0 revision
    # qualify: bare, fuzzy and range atoms stay the resolver's domain
    # (an archive legitimately satisfies bare deps from historical r0s
    # it keeps forever, and fully dangling atoms are left alone).
    published_versions: dict[str, list] = {}
    for row in conn.execute("SELECT name, version FROM packages"):
        published_versions.setdefault(row["name"], []).append(row["version"])
    for ident in sorted(staged_identities):
        for edge in staged_depends.get(ident, []):
            match = DEPEND_ATOM_RE.fullmatch(edge)
            if not match or "/" in edge or ":" in edge:
                continue
            if match.group(3) != "=":
                continue
            want = match.group(4)
            if VERSION_BASE_RE.fullmatch(want) is None or pkgrel_of(want) != 0:
                continue
            target = match.group(1)
            universe = list(published_versions.get(target, []))
            universe.extend(version for (stage_name, version) in staged_identities
                            if stage_name == target)
            if (depend_satisfied(apk_bin, edge, universe)
                    and not depend_satisfied(
                        apk_bin, edge,
                        [v for v in universe if pkgrel_of(v) != 0])):
                raise RepoDbError(
                    f"staged {ident[0]}-{ident[1]} depends on '{edge}',"
                    " satisfiable only by r0 (broken live dependency: r0 is"
                    " inadmissible in the live view and is never retained to"
                    " satisfy it - fix the consumer recipe at r1+)")
    tsv_parsed = parse_tsv(tsv_path)
    notices: list[str] = []
    for path, claimants in shared_init.items():
        notices.append(
            f"shared init selector: {path} co-owned by "
            f"{', '.join(claimants)} (del-then-add init swaps; "
            "never --force-overwrite)")
    if tsv_parsed is None:
        active_count = conn.execute(
            "SELECT COUNT(*) c FROM reservations WHERE status='ACTIVE'").fetchone()["c"]
        if any(accounts.get("users") or accounts.get("groups") or accounts.get("files")
               for accounts in (item["accounts"] for item in info.values())) or active_count:
            raise RepoDbError(
                f"accounts authority is missing: {tsv_path} "
                "(set SAPHIRA_ACCOUNTS_TSV or install saphira-baselayout)")
        notices.append(f"no TSV reservations and no declarations; account gate skipped ({tsv_path} absent)")
    else:
        tsv_users, tsv_groups = tsv_parsed
        # A staged successor supersedes its repo-newest declaration in the
        # union check (mirrors the file gate's newer-or-novel merge):
        # without this, the first upgrade of any identity-declaring
        # package under the SQLite gate false-collides with itself.
        # Published r0 declarations are history, never active identity
        # claims (mirrors the file-gate r0 filter above). The eternal
        # reservation ledger still binds everything including r0
        # tombstones - see check_reservations, deliberately unfiltered.
        staged_newer = {name for (name, version) in staged_identities
                        if name in newest and apk_newer(apk_bin, version, newest[name])}
        decls = [(label, decl) for label, package, decl in active_declarations(conn)
                 if package not in staged_newer and package not in r0_names]
        decls += [(label, decl) for label, _package, decl in staged_decl_list]
        check_union(tsv_users, tsv_groups, decls)
        check_reservations(conn, staged_decl_list)
        mk = makepkg()
        for filename in sorted(info):
            item = staged_receipts.get(filename, {"accounts": {"users": [], "groups": [], "dirs": [], "files": []}})
            label = f"staged:{item.get('name', '?')}-{item.get('version', '?')}"
            check_file_references(label, item["accounts"])
            for entry in item["accounts"].get("groups", []):
                if int(entry["gid"]) > mk.PREFERRED_MAX_ID:
                    notices.append(
                        f"{label} group {entry['name']} GID {entry['gid']} is in the "
                        f"200..887 expansion range (preferred 0..{mk.PREFERRED_MAX_ID})")
            for entry in item["accounts"].get("users", []):
                if int(entry["uid"]) > mk.PREFERRED_MAX_ID:
                    notices.append(
                        f"{label} user {entry['name']} UID {entry['uid']} is in the "
                        f"200..887 expansion range (preferred 0..{mk.PREFERRED_MAX_ID})")
        check_legacy_union(info, decls)
    return info, notices


# ---------------------------------------------------------------------------
# staged publication apply (inside the publication transaction)
# ---------------------------------------------------------------------------

def apply_staged(conn: sqlite3.Connection, apk_bin: str, repo_dir: str | Path,
                 staged: dict[str, dict], published_at: str,
                 notices: list[str]) -> None:
    """Apply staged packages to the ledger: upsert package/file/account
    rows, recompute newest flags, advance reservations (new bindings
    ACTIVE, dropped bindings TOMBSTONED — never deleted). The caller holds
    the writer lock and runs this inside BEGIN IMMEDIATE after installing
    the APKs, so row shas are read from the installed repository copies."""
    repo_dir = Path(repo_dir)
    for filename in sorted(staged):
        item = staged[filename]
        name, version = item["name"], item["version"]
        installed = repo_dir / filename
        if not installed.is_file():
            raise RepoDbError(f"staged package not installed: {filename}")
        digest = sha256_file(installed)
        decl = item.get("accounts", {"users": [], "groups": [], "dirs": [], "files": []})
        _, decl_sha = canonical_declaration(decl.get("users", []),
                                            decl.get("groups", []), decl.get("dirs", []))
        row = conn.execute(
            "SELECT package_id FROM packages WHERE name=? AND version=?",
            (name, version)).fetchone()
        if row is None:
            conn.execute(
                "INSERT INTO packages(name, version, pkgrel, nvr, apk_sha256, is_newest, published_at)"
                " VALUES (?, ?, ?, ?, ?, 0, ?)",
                (name, version, pkgrel_of(version), f"{name}-{version}", digest, published_at),
            )
            package_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
        else:
            package_id = row["package_id"]
            if conn.execute("SELECT apk_sha256 FROM packages WHERE package_id=?",
                            (package_id,)).fetchone()["apk_sha256"] != digest:
                raise RepoDbError(f"content changed under immutable NVR: {filename}")
            conn.execute("DELETE FROM state_dirs WHERE package_id=?", (package_id,))
            conn.execute("DELETE FROM users WHERE package_id=?", (package_id,))
            conn.execute("DELETE FROM groups WHERE package_id=?", (package_id,))
            conn.execute("DELETE FROM files WHERE package_id=?", (package_id,))
        conn.executemany("INSERT INTO files(package_id, path) VALUES (?, ?)",
                         [(package_id, p) for p in item["files"]])
        for u in decl.get("users", []):
            conn.execute(
                "INSERT INTO users(package_id, name, uid, primary_group, home, shell, declaration_sha256)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (package_id, u["name"], int(u["uid"]), u["primary"],
                 u["home"], u["shell"], decl_sha))
        for g in decl.get("groups", []):
            conn.execute(
                "INSERT INTO groups(package_id, name, gid, declaration_sha256)"
                " VALUES (?, ?, ?, ?)",
                (package_id, g["name"], int(g["gid"]), decl_sha))
        for d in decl.get("dirs", []):
            conn.execute(
                'INSERT INTO state_dirs(package_id, path, mode, owner, "group")'
                " VALUES (?, ?, ?, ?, ?)",
                (package_id, d["path"], d["mode"], d["owner"], d["group"]))
    # Newest flags + reservation advances for every touched package name.
    for name in sorted({item["name"] for item in staged.values()}):
        versions = [r["version"] for r in conn.execute(
            "SELECT version FROM packages WHERE name=?", (name,)).fetchall()]
        best = versions[0]
        for version in versions[1:]:
            if apk_newer(apk_bin, version, best):
                best = version
        conn.execute("UPDATE packages SET is_newest=0 WHERE name=?", (name,))
        conn.execute("UPDATE packages SET is_newest=1 WHERE name=? AND version=?",
                     (name, best))
        new_decl = None
        for filename in sorted(staged):
            if staged[filename]["name"] == name:
                new_decl = staged[filename].get("accounts",
                                                {"users": [], "groups": [], "dirs": []})
        if new_decl is None:
            continue
        live_names = ({e["name"] for e in new_decl.get("users", [])},
                      {e["name"] for e in new_decl.get("groups", [])})
        for entry in new_decl.get("groups", []):
            upsert_reservation(conn, "group", entry["name"], int(entry["gid"]),
                               name, f"{name}-{best}", new_decl, notices)
        for entry in new_decl.get("users", []):
            upsert_reservation(conn, "user", entry["name"], int(entry["uid"]),
                               name, f"{name}-{best}", new_decl, notices)
        for (kind, sub) in (("user", live_names[0]), ("group", live_names[1])):
            for row in conn.execute(
                    "SELECT name FROM reservations"
                    " WHERE kind=? AND owning_package=? AND status='ACTIVE'",
                    (kind, name)).fetchall():
                if row["name"] not in sub:
                    conn.execute(
                        "UPDATE reservations SET status='TOMBSTONED', last_nvr=?"
                        " WHERE kind=? AND name=?", (f"{name}-{best}", kind, row["name"]))
                    notices.append(
                        f"reservation tombstoned: {kind} {row['name']}"
                        f" (dropped by {name}-{best}; IDs never recycle)")


# ---------------------------------------------------------------------------
# read-only query API (viewer)
# ---------------------------------------------------------------------------

def q_summary(conn: sqlite3.Connection) -> dict:
    pkgs = conn.execute("SELECT COUNT(*) c FROM packages").fetchone()["c"]
    newest = conn.execute("SELECT COUNT(*) c FROM packages WHERE is_newest=1").fetchone()["c"]
    files = conn.execute("SELECT COUNT(*) c FROM files").fetchone()["c"]
    users = conn.execute("SELECT COUNT(*) c FROM users").fetchone()["c"]
    groups = conn.execute("SELECT COUNT(*) c FROM groups").fetchone()["c"]
    active = conn.execute("SELECT COUNT(*) c FROM reservations WHERE status='ACTIVE'").fetchone()["c"]
    tombs = conn.execute("SELECT COUNT(*) c FROM reservations WHERE status='TOMBSTONED'").fetchone()["c"]
    return {"apk_identities": pkgs, "newest_names": newest, "owned_paths": files,
            "declared_users": users, "declared_groups": groups,
            "active_reservations": active, "tombstoned_reservations": tombs}


def q_owner(conn: sqlite3.Connection, path: str) -> list[dict]:
    path = path.lstrip("/")
    return [dict(r) for r in conn.execute(
        "SELECT p.name, p.version, p.is_newest FROM files f"
        " JOIN packages p ON p.package_id=f.package_id"
        " WHERE f.path=? ORDER BY p.name, p.version", (path,)).fetchall()]


def q_conflicts(conn: sqlite3.Connection) -> list[dict]:
    owners = newest_owners(conn)
    return [{"path": p, "owners": m} for p, m in sorted(owners.items()) if len(m) > 1]


def q_history(conn: sqlite3.Connection, name: str) -> dict:
    nvrs = [dict(r) for r in conn.execute(
        "SELECT version, apk_sha256, is_newest, published_at FROM packages"
        " WHERE name=? ORDER BY version", (name,)).fetchall()]
    res = [dict(r) for r in conn.execute(
        "SELECT kind, name, numeric_id, owning_package, first_nvr, last_nvr, status"
        " FROM reservations WHERE owning_package=? ORDER BY kind, name", (name,)).fetchall()]
    return {"package": name, "nvrs": nvrs, "reservations": res}


def utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

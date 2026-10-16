#!/bin/sh

# Identity-transition census tests: sanctioned renumbers pass exactly,
# everything else still fails closed.
#
# Exercises repo_db.derive_ledger / load_transitions directly with
# synthetic census data (no APKs, no network, no repository), plus the
# shipped identity-transitions data file. Covers the polkitd 127->156
# sanction and every mandated negative: undeclared, wrong package,
# wrong identity, wrong kind, wrong ids, reversed, second renumber,
# and malformed declaration files.
#
# usage: identity-transitions.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
check_base=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$check_base"

"${SAPHIRA_PYTHON:-python3}" - "$source_root" "$check_base" <<'PY'
import importlib.machinery
import importlib.util
import sys
from pathlib import Path

source_root, check_base = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader(
    "repo_db_rules", str(Path(source_root) / "saphira-packager/files/repo_db.py"))
spec = importlib.util.spec_from_loader("repo_db_rules", loader)
rdb = importlib.util.module_from_spec(spec)
loader.exec_module(rdb)

passed = [0]


def check(label, cond):
    if not cond:
        print(f"identity-transitions: FAIL: {label}", file=sys.stderr)
        sys.exit(1)
    passed[0] += 1


def expect_raise(label, fn):
    try:
        fn()
    except rdb.RepoDbError:
        passed[0] += 1
        return
    print(f"identity-transitions: FAIL (no refusal): {label}", file=sys.stderr)
    sys.exit(1)


def decl(uid=None, gid=None):
    d = {"users": [], "groups": [], "dirs": [], "files": []}
    if uid is not None:
        d["users"] = [{"name": "polkitd", "uid": str(uid),
                       "primary": "polkitd", "home": "/var/empty",
                       "shell": "/sbin/nologin"}]
    if gid is not None:
        d["groups"] = [{"name": "polkitd", "gid": str(gid)}]
    return d


def census(*versions):
    return {f"polkit-{v}.apk": {"name": "polkit", "version": v}
            for v in versions}


SANCTIONED = {
    ("polkit", "group", "polkitd"): (127, 156, "polkit-127-r2"),
    ("polkit", "user", "polkitd"): (127, 156, "polkit-127-r2"),
}

# 1. exact sanctioned group transition passes, with audit notice
notices = []
rows = rdb.derive_ledger(
    "apk", census("127-r1", "127-r2"),
    {"polkit-127-r1.apk": decl(gid=127),
     "polkit-127-r2.apk": decl(gid=156)},
    notices, dict(SANCTIONED))
grow = [r for r in rows if r[0] == "group" and r[1] == "polkitd"][0]
check("sanctioned group passes with new id", grow[2] == 156)
check("sanctioned group keeps first nvr", grow[4] == "polkit-127-r1")
check("sanctioned group stays active", grow[6] == "ACTIVE")
check("sanctioned group emits notice",
      any("sanctioned identity transition: group polkitd 127 -> 156 "
          "at polkit-127-r2" in n for n in notices))

# 2. exact sanctioned user transition passes
notices = []
rows = rdb.derive_ledger(
    "apk", census("127-r1", "127-r2"),
    {"polkit-127-r1.apk": decl(uid=127),
     "polkit-127-r2.apk": decl(uid=156)},
    notices, dict(SANCTIONED))
urow = [r for r in rows if r[0] == "user" and r[1] == "polkitd"][0]
check("sanctioned user passes with new id", urow[2] == 156)
check("sanctioned user emits notice",
      any("user polkitd 127 -> 156" in n for n in notices))

# 3. undeclared transition fails closed
expect_raise("undeclared group change",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156)},
                 [], {}))

# 4. wrong package fails
expect_raise("wrong package",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156)},
                 [], {("other", "group", "polkitd"): (127, 156, "other-1-r1")}))

# 5. wrong identity fails
expect_raise("wrong identity",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156)},
                 [], {("polkit", "group", "other"): (127, 156, "polkit-127-r2")}))

# 6. wrong kind fails (group exemption does not cover a user change)
expect_raise("wrong kind",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(uid=127),
                  "polkit-127-r2.apk": decl(uid=156)},
                 [], {("polkit", "group", "polkitd"): (127, 156, "polkit-127-r2")}))

# 7a. wrong new id fails
expect_raise("wrong new id",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156)},
                 [], {("polkit", "group", "polkitd"): (127, 999, "polkit-127-r2")}))

# 7b. wrong old id fails
expect_raise("wrong old id",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156)},
                 [], {("polkit", "group", "polkitd"): (0, 156, "polkit-127-r2")}))

# 7c. wrong introducing NVR fails
expect_raise("wrong nvr",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156)},
                 [], {("polkit", "group", "polkitd"): (127, 156, "polkit-127-r9")}))

# 8. later unexpected second renumber fails
expect_raise("second renumber",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2", "127-r3"),
                 {"polkit-127-r1.apk": decl(gid=127),
                  "polkit-127-r2.apk": decl(gid=156),
                  "polkit-127-r3.apk": decl(gid=200)},
                 [], dict(SANCTIONED)))

# 9. reversed history fails
expect_raise("reversed",
             lambda: rdb.derive_ledger(
                 "apk", census("127-r1", "127-r2"),
                 {"polkit-127-r1.apk": decl(gid=156),
                  "polkit-127-r2.apk": decl(gid=127)},
                 [], dict(SANCTIONED)))

# 10. loader: good file parses, malformed files refuse
good = Path(check_base) / "transitions-good"
good.write_text("polkit group polkitd 127 156 polkit-127-r2\n", encoding="utf-8")
check("loader parses good file",
      rdb.load_transitions(str(good)) ==
      {("polkit", "group", "polkitd"): (127, 156, "polkit-127-r2")})
check("missing file means no exemptions",
      rdb.load_transitions(str(Path(check_base) / "transitions-absent")) == {})
bad_cases = {
    "field-count": "polkit group polkitd 127 156\n",
    "kind": "polkit service polkitd 127 156 polkit-127-r2\n",
    "non-numeric": "polkit group polkitd abc 156 polkit-127-r2\n",
    "same-ids": "polkit group polkitd 156 156 polkit-127-r2\n",
    "foreign-nvr": "polkit group polkitd 127 156 other-1-r1\n",
    "duplicate": ("polkit group polkitd 127 156 polkit-127-r2\n"
                  "polkit group polkitd 127 156 polkit-127-r2\n"),
}
for label, content in bad_cases.items():
    path = Path(check_base) / f"transitions-bad-{label}"
    path.write_text(content, encoding="utf-8")

    def load(path=path):
        return rdb.load_transitions(str(path))

    expect_raise(f"malformed file refuses ({label})", load)

# 11. shipped data file parses and authorises the real history shape
shipped = rdb.load_transitions()
check("shipped file carries the polkitd group transition",
      shipped.get(("polkit", "group", "polkitd")) == (127, 156, "polkit-127-r2"))
check("shipped file carries the polkitd user transition",
      shipped.get(("polkit", "user", "polkitd")) == (127, 156, "polkit-127-r2"))
notices = []
rdb.derive_ledger(
    "apk", census("127-r1", "127-r2"),
    {"polkit-127-r1.apk": decl(uid=127, gid=127),
     "polkit-127-r2.apk": decl(uid=156, gid=156)},
    notices)
check("default path consumes the shipped file",
      sum("sanctioned identity transition" in n for n in notices) == 2)

print(f"identity-transition census tests: OK ({passed[0]} checks)")
PY

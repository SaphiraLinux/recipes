#!/bin/sh
# tests/dashboard.sh: functional test for saphira-build-dashboard.
#
# Usage: tests/dashboard.sh <path-to-saphira-build-dashboard>
#
# Hermetic: builds a fixture queue database under scratch, serves it on
# 127.0.0.1:18899, and asserts TODAY/History contents, refusal styling,
# method/path refusals, and that the fixture is byte-identical
# afterwards (the server must not write). The server is killed on exit.
set -eu

DASH=${1:?usage: tests/dashboard.sh <path-to-saphira-build-dashboard>}
PORT=18899
ROOT=${SAPHIRA_TMPDIR:-/build/tmp}/dashboard-test-$$
DB=$ROOT/queue.db
URL=http://127.0.0.1:$PORT

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS %s\n' "$1"; }

[ -x "$DASH" ] || fail "not executable: $DASH"

cleanup() {
	if [ -n "${SRVPID:-}" ]; then kill "$SRVPID" 2>/dev/null || true; fi
	rm -rf "$ROOT"
}
trap cleanup EXIT INT TERM
mkdir -p "$ROOT"

# Fixture: one published PASS today (green), one unpublished PASS today
# (amber awaiting signing), one FAIL today with BUILD-pass plus
# INSTALL-fail stages and an over-long detail (red, truncated), one
# refusal today (hatched red), one running, one queued (started NULL),
# one published PASS yesterday, plus one active SBU baseline row.
# Schemas mirror the live queue database (builds + sbu_baseline as
# created by saphira-build).
python3 - "$DB" <<'EOF'
import sqlite3, sys, time
db = sys.argv[1]
fmt = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
now = time.time()
today, yesterday = fmt(now), fmt(now - 86400)
conn = sqlite3.connect(db)
conn.execute(
    "CREATE TABLE builds(id INTEGER PRIMARY KEY, package TEXT,"
    " version TEXT, revision TEXT, recipe_hash TEXT, state TEXT,"
    " result_json TEXT, log_dir TEXT, commit_hash TEXT, queued_at TEXT,"
    " started_at TEXT, finished_at TEXT, published_at TEXT,"
    " builder_pid INTEGER, boot_id TEXT, duration_s REAL, cpu_s REAL,"
    " peak_rss_mb REAL, timings_json TEXT, arch TEXT, builder_host TEXT)")
conn.executemany(
    "INSERT INTO builds(package, version, revision, state, result_json,"
    " duration_s, cpu_s, peak_rss_mb, arch, builder_host,"
    " queued_at, started_at, finished_at, published_at)"
    " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    [("todaypkg", "1.0", 1, "PASS", '{"attempt": null}',
      10.0, 8.0, 100.0, "x86_64", "egg", today, today, today, today),
     ("waiterpkg", "0.2", 1, "PASS", '{"attempt": null}',
      5.0, 4.0, 50.0, "x86_64", "egg", today, today, today, None),
     ("failpkg", "1.5", 2, "FAIL",
      '{"attempt": "build", "stages": {"BUILD": {"status": "pass",'
      ' "detail": "buildpkg rc=0"}, "INSTALL": {"status": "fail",'
      ' "detail": "post-install exit 1: ' + 'x' * 200 + '"}},'
      ' "blockers": []}',
      30.0, 20.0, 200.0, "x86_64", "egg", today, today, today, None),
     ("refusalsample", "2.0", 3, "FAIL",
      '{"attempt": "refusal", "stages": {"BUILD": {"status": "fail",'
      ' "detail": "buildpkg rc=2"}}, "blockers": []}',
      1.0, 0.3, 27.5, "x86_64", "egg", today, today, today, None),
     ("runpkg", "0.5", 1, "BUILDING", None,
      None, None, None, "x86_64", "egg", today, today, None, None),
     ("queuepkg", "0.1", 1, "QUEUED", None,
      None, None, None, "x86_64", "egg", today, None, None, None),
     ("yesterdaypkg", "9.9", 2, "PASS", '{"attempt": null}',
      60.0, 50.0, 500.0, "x86_64", "egg",
      yesterday, yesterday, yesterday, yesterday)])
conn.execute(
    "CREATE TABLE sbu_baseline(id INTEGER PRIMARY KEY, package TEXT NOT NULL,"
    " version TEXT, revision TEXT, recipe_commit TEXT,"
    " arch TEXT, builder_host TEXT, cache_policy TEXT NOT NULL,"
    " wall_s REAL NOT NULL, cpu_s REAL,"
    " active INTEGER NOT NULL DEFAULT 0, calibrated_at TEXT NOT NULL)")
conn.execute(
    "INSERT INTO sbu_baseline(package, version, revision, arch,"
    " builder_host, cache_policy, wall_s, cpu_s, active, calibrated_at)"
    " VALUES('musl', '1.2.6', 6, 'x86_64', 'egg', 'cold', 120.0, 100.0,"
    " 1, '%s')" % today)
conn.commit()
conn.close()
EOF
pass "fixture-built"

H1=$(sha256sum "$DB" | cut -d' ' -f1)

"$DASH" --bind 127.0.0.1 --port "$PORT" --db "$DB" &
SRVPID=$!

i=0
while [ "$i" -lt 50 ]; do
	if python3 -c 'import sys,urllib.request; urllib.request.urlopen(sys.argv[1], timeout=1).read(1)' "$URL/" 2>/dev/null; then break; fi
	i=$((i + 1)); sleep 0.1
done
[ "$i" -lt 50 ] || fail "server did not listen on 127.0.0.1:$PORT"
pass "server-listens-ipv4"

export DASH_URL=$URL
python3 - <<'EOF'
import os, sys, urllib.request, urllib.error
base = os.environ["DASH_URL"]

def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        sys.exit(1)

def get(path):
    with urllib.request.urlopen(base + path, timeout=5) as r:
        return r.status, r.read().decode("utf-8")

s, today = get("/")
check("today-200", s == 200)
check("counts-red", "1 failed today" in today)
check("counts-amber", "3 pending / running / awaiting signing" in today)
check("counts-green", "1 published" in today)
check("counts-refused", "1 refused (never built)" in today)
check("today-has-today", "todaypkg" in today)
check("today-has-waiter", "waiterpkg" in today and "AWAITING SIGNING" in today)
check("today-has-fail", "failpkg" in today)
check("today-has-running", "runpkg" in today and "RUNNING" in today)
check("today-has-queued", "queuepkg" in today and "QUEUED" in today)
check("today-hides-yesterday", "yesterdaypkg" not in today)
check("refused-text", 'class="refused"' in today and "refusalsample" in today and "REFUSED" in today)
check("refused-legend", "never built" in today)
check("failed-stage", "INSTALL" in today and "post-install exit 1" in today)
check("failed-truncated", "…" in today)
check("failed-not-build-detail", "rc=0" not in today)
check("dots", "dot red" in today and "dot amber" in today and "dot green" in today)
check("legend-awaiting", "awaiting signing" in today)
check("tabs-present", 'href="/history"' in today)

s, hist = get("/history")
check("history-200", s == 200)
check("history-counts", "1 failed shown" in hist and "2 published" in hist)
check("history-has-yesterday", "yesterdaypkg" in hist)
check("history-has-today", "todaypkg" in hist)
check("history-published-text", "PUBLISHED" in hist)
check("history-has-sbu", "SBU baselines" in hist and "musl" in hist)
check("tabs-present-history", 'href="/"' in hist)

r = urllib.request.Request(base + "/", method="HEAD")
with urllib.request.urlopen(r, timeout=5) as resp:
    check("head-200-empty", resp.status == 200 and resp.read() == b"")

for method in ("POST", "PUT", "DELETE"):
    req = urllib.request.Request(base + "/", data=b"", method=method)
    try:
        urllib.request.urlopen(req, timeout=5)
        check(method + "-405", False)
    except urllib.error.HTTPError as e:
        check(method + "-405", e.code == 405)

try:
    urllib.request.urlopen(base + "/nope", timeout=5)
    check("unknown-404", False)
except urllib.error.HTTPError as e:
    check("unknown-404", e.code == 404)
EOF

H2=$(sha256sum "$DB" | cut -d' ' -f1)
[ "$H1" = "$H2" ] || fail "fixture database changed (server wrote)"
pass "fixture-byte-identical"

# The mode=ro handle must refuse writes even if asked to.
python3 - "$DB" <<'EOF'
import sqlite3, sys
from urllib.request import pathname2url
conn = sqlite3.connect("file:%s?mode=ro" % pathname2url(sys.argv[1]),
                       uri=True, timeout=5)
try:
    conn.execute("CREATE TABLE probe_dashboard_write(x)")
    print("FAIL ro-handle-refuses-write")
    sys.exit(1)
except sqlite3.OperationalError:
    print("PASS ro-handle-refuses-write")
EOF

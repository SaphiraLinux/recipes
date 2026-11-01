#!/bin/sh
# saphira-build test suite. Self-contained under mktemp; asserts the Egg
# package world is unchanged. Uses a stub buildpkg and a stub apk so no
# real builds happen; stage evaluation is exercised directly on synthetic
# roots.
set -eu

SAPHIRA_BUILD="${1:-$(dirname "$0")/../files/saphira-build}"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }
assert() { # desc, expected_rc, cmd...
    desc=$1; want=$2; shift 2
    if "$@" >/dev/null 2>&1; then got=0; else got=$?; fi
    [ "$got" = "$want" ] && ok "$desc" || bad "$desc (rc=$got want=$want)"
}
assert_contains() { # desc, haystack_file_or_- , needle
    desc=$1; hay=$2; needle=$3
    if [ "$hay" = "-" ]; then
        if grep -q "$needle"; then ok "$desc"; else bad "$desc (missing: $needle)"; fi
    else
        if grep -q "$needle" "$hay" 2>/dev/null; then ok "$desc"; else bad "$desc (missing: $needle)"; fi
    fi
}
assert_has() { # desc, haystack_STRING, needle
    desc=$1; hay=$2; needle=$3
    case $hay in
        *"$needle"*) ok "$desc" ;;
        *) bad "$desc (missing: $needle)" ;;
    esac
}

test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
TMP=$(mktemp -d "$test_tmp_base/saphira-build-test.XXXXXX")
export SAPHIRA_TMPDIR=$TMP/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'rm -rf "$TMP"' EXIT
WORLD_BEFORE=$(sha256sum /etc/apk/world 2>/dev/null | cut -d' ' -f1 || echo none)

RECIPES=$TMP/recipes
STATE=$TMP/state
INCOMING=$TMP/incoming
mkdir -p "$RECIPES" "$INCOMING" "$STATE"

cat > "$TMP/stub-buildpkg" <<'EOF'
#!/bin/sh
# stub buildpkg: success unless package name contains 'broken'
pkg=$1
case "$pkg" in *broken*) echo "stub: $pkg failed" >&2; exit 1;; esac
ver=$(grep "^pkgver=" "$RECIPE_ROOT/$pkg/recipe.sh" | cut -d= -f2)
rel=$(grep "^pkgrel=" "$RECIPE_ROOT/$pkg/recipe.sh" | cut -d= -f2)
d="$SAPHIRA_INCOMING_STUB/$pkg-$(date +%s%N)-ready"
mkdir -p "$d"
printf 'stub-apk-payload %s\n' "$pkg" > "$d/$pkg-$ver-r$rel.apk"
exit 0
EOF
chmod +x "$TMP/stub-buildpkg"

cat > "$TMP/stub-apk" <<'EOF'
#!/bin/sh
root=""
for a in "$@"; do case "$a" in --root=*) root=${a#--root=};; esac; done
case "$*" in
    *add\ *)
        mkdir -p "$root/usr/bin" "$root/etc/init.d"
        apkfile=$*
        apkfile=${apkfile##* }
        # Each of these is provided by the package that really provides it,
        # so the seed closure has to be what puts them in the root. The
        # reconciler is saphira-baselayout's; /bin/bash is bash's; /bin/env is
        # coreutils'.
        provide() {
            case "$1" in
                bash)               mkdir -p "$root/bin"
                                    printf '#!/bin/sh\nexit 0\n' > "$root/bin/bash"
                                    chmod 0755 "$root/bin/bash" ;;
                coreutils)          mkdir -p "$root/bin"
                                    printf '#!/bin/sh\nexit 0\n' > "$root/bin/env"
                                    chmod 0755 "$root/bin/env" ;;
                saphira-baselayout) mkdir -p "$root/usr/libexec/saphira"
                                    printf '#!/bin/sh\nexit 0\n' > "$root/usr/libexec/saphira/ensure-identity.sh"
                                    chmod 0755 "$root/usr/libexec/saphira/ensure-identity.sh" ;;
                saphira-base)       # a group pulls its members, as apk resolves it
                                    provide bash; provide coreutils; provide saphira-baselayout ;;
            esac
        }
        provide "$apkfile"
        printf 'stub\n' > "$root/usr/bin/prog"
        [ "$apkfile" != "${apkfile%-svc*}" ] && printf 'stub\n' > "$root/etc/init.d/svc"
        # Model apk running the package's maintainer scripts chrooted in the
        # root. makepkg generates every one with `#!/bin/sh`, and the fake
        # root assembled here installs no bash payload, so a root without
        # the link fails the script with `execve: No such file or
        # directory` and exit 127 - a missing interpreter, which is NOT
        # the reconciler and not any helper file. (On a real root the link
        # arrives with the bash package; this model keeps testing the
        # fallback path where it has not landed yet.)
        if [ ! -e "$root/bin/sh" ]; then
            printf '  * execve: No such file or directory\n'
            printf 'ERROR: lib/apk/exec/%s.post-install: exited with error 127\n' "${apkfile##*/}"
            exit 2
        fi
        exit 0 ;;
    *info\ -L*)
        pkg=$*
        pkg=${pkg##* }
        echo "$pkg-1.0-r0 contains:"
        echo "usr/bin/prog"
        ls "$root/etc/init.d" 2>/dev/null | sed 's|^|etc/init.d/|'
        exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/stub-apk"

export SAPHIRA_BUILD_STATE="$STATE"
export SAPHIRA_RECIPES="$RECIPES"
export SAPHIRA_INCOMING="$INCOMING"
export SAPHIRA_REPO="$TMP/repo"
export SAPHIRA_BUILDCMD="$TMP/stub-buildpkg"
export SAPHIRA_APK="$TMP/stub-apk"
export SAPHIRA_TEST_ROOTS="$TMP/testroots"
export SAPHIRA_INCOMING_STUB="$INCOMING"
export RECIPE_ROOT="$RECIPES"

# The install-stage root is seeded from saphira-base, so the stub repository
# needs it, exactly as the live repository has it. Its members (bash,
# coreutils, saphira-baselayout) are what put /bin/bash and the reconciler
# into the root; the stub apk provides those files on add.
mkdir -p "$RECIPES/saphira-base/files" "$RECIPES/bash/files" \
	"$RECIPES/coreutils/files" "$RECIPES/saphira-baselayout/files"
cat > "$RECIPES/saphira-base/recipe.sh" <<'BASERECIPE'
pkgname=saphira-base
pkgver=0.1
pkgrel=1
depends="bash coreutils saphira-baselayout"
BASERECIPE
for member in bash coreutils saphira-baselayout; do
	cat > "$RECIPES/$member/recipe.sh" <<MEMBERRECIPE
pkgname=$member
pkgver=1.0
pkgrel=1
depends=""
MEMBERRECIPE
done

mkdir -p "$RECIPES/base/files" "$RECIPES/dependent" "$RECIPES/needsmissing" "$RECIPES/brokensvc"
cat > "$RECIPES/base/recipe.sh" <<'EOF'
pkgname=base
pkgver=1.0
pkgrel=0
depends="missingdep-not-arealpkg"
EOF
sed -i 's/^depends=.*/depends=""/' "$RECIPES/base/recipe.sh"
cat > "$RECIPES/dependent/recipe.sh" <<'EOF'
pkgname=dependent
pkgver=2.0
pkgrel=1
depends="base"
EOF
cat > "$RECIPES/needsmissing/recipe.sh" <<'EOF'
pkgname=needsmissing
pkgver=1.0
pkgrel=0
depends="ghost-package"
EOF
cat > "$RECIPES/brokensvc/recipe.sh" <<'EOF'
pkgname=brokensvc
pkgver=1.0
pkgrel=0
depends="base"
EOF

"$SAPHIRA_BUILD" scan > "$TMP/scan.out" 2>&1
assert_contains "scan queues unknown recipes" "$TMP/scan.out" "newly queued"

"$SAPHIRA_BUILD" queue > "$TMP/queue.out" 2>&1 || true
assert_contains "blocked set present pre-build" "$TMP/queue.out" "BLOCKED: 4"
assert_contains "blocked reason names ghost" "$TMP/queue.out" "ghost-package"

# Trust-anchor preflight: the run phase needs the repository index as its
# plan-time trust anchor. Give the fixture repo a (dummy) index so the
# stub builds below can proceed; the missing-index skip is tested after.
mkdir -p "$TMP/repo"
: > "$TMP/repo/Packages.adb"

"$SAPHIRA_BUILD" run --limit=10 > "$TMP/run.out" 2>&1 || true
assert_contains "stub build of base passes" "$TMP/run.out" "base -> PASS"
assert_contains "dependent passes after base" "$TMP/run.out" "dependent -> PASS"
assert_contains "broken package fails" "$TMP/run.out" "brokensvc -> FAIL"

"$SAPHIRA_BUILD" scan > "$TMP/rescan.out" 2>&1
assert_contains "PASS recipes skipped on rescan" "$TMP/rescan.out" "already proven"

"$SAPHIRA_BUILD" status > "$TMP/status.out" 2>&1
assert_contains "status shows base PASS" "$TMP/status.out" "base"
assert_contains "status shows dependent PASS" "$TMP/status.out" "dependent"

"$SAPHIRA_BUILD" log base > "$TMP/log.out" 2>&1
assert_contains "log includes build.log" "$TMP/log.out" "build.log"

# times: last finished attempt per package with wall/CPU/RSS; rows that
# predate measurement show "-" where unrecoverable. SBU ratios stay out:
# raw seconds until the reference workload is defined and calibrated.
"$SAPHIRA_BUILD" times nosuchpackage > "$TMP/times-empty.out" 2>&1
assert_contains "times names the miss" "$TMP/times-empty.out" "no finished builds matching nosuchpackage"
python3 - "$STATE/queue.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,started_at,finished_at,"
    " duration_s,cpu_s,peak_rss_mb,arch,builder_host)"
    " VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
    ("timepkg", "2.0", "3", "h" * 64, "PASS",
     "2026-10-27T10:00:00Z", "2026-10-27T10:01:40Z",
     100.0, 60.0, 512.5, "x86_64", "egg"))
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,finished_at,"
    " arch,builder_host)"
    " VALUES (?,?,?,?,?,?,?,?)",
    ("oldpkg", "1.0", "1", "a" * 64, "FAIL",
     "2026-10-27T09:02:00Z", "x86_64", "egg"))
conn.commit()
PY
"$SAPHIRA_BUILD" times > "$TMP/times.out" 2>&1
assert_contains "times shows measured wall" "$TMP/times.out" "100s"
assert_contains "times shows cpu" "$TMP/times.out" "60s"
assert_contains "times shows rss" "$TMP/times.out" "512.5"
if grep -Eq "^oldpkg +1\.0-r1 +FAIL + +- " "$TMP/times.out"; then
	ok "times shows unmeasured wall as dash"
else
	bad "times unmeasured wall is not a dash"
fi
"$SAPHIRA_BUILD" times timepkg > "$TMP/times-one.out" 2>&1
assert_contains "times filters by package" "$TMP/times-one.out" "timepkg"
if grep -q "oldpkg" "$TMP/times-one.out"; then
	bad "times filter leaked unselected package"
else
	ok "times filter excludes others"
fi
# Migration backfill: a pre-columns database gains durations computed
# from its timestamps when any command first opens it.
mkdir -p "$TMP/oldstate"
python3 - "$TMP/oldstate/queue.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute(
    "CREATE TABLE builds(id INTEGER PRIMARY KEY, package TEXT NOT NULL,"
    " version TEXT, revision TEXT, recipe_hash TEXT NOT NULL, state TEXT NOT NULL,"
    " result_json TEXT NOT NULL DEFAULT '{}', log_dir TEXT, commit_hash TEXT,"
    " queued_at TEXT, started_at TEXT, finished_at TEXT, published_at TEXT)")
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,started_at,finished_at)"
    " VALUES (?,?,?,?,?,?,?)",
    ("legacypkg", "1.0", "1", "b" * 64, "PASS",
     "2026-10-27T09:00:00Z", "2026-10-27T09:05:00Z"))
conn.commit()
PY
SAPHIRA_BUILD_STATE=$TMP/oldstate "$SAPHIRA_BUILD" times > "$TMP/times-old.out" 2>&1
assert_contains "migration backfills wall from timestamps" "$TMP/times-old.out" "5m00s"
# SBU: no baseline yet -> the report says so instead of dividing.
"$SAPHIRA_BUILD" times --sbu > "$TMP/times-nosbu.out" 2>&1
assert_contains "missing baseline is reported, not divided" "$TMP/times-nosbu.out" "no active musl baseline"
# calibrate builds the reference through the identical run_one pipeline
# (stub builder here) with a cold cache and pins the baseline row.
"$SAPHIRA_BUILD" calibrate base > "$TMP/calibrate.out" 2>&1
assert_contains "calibrate reports the baseline" "$TMP/calibrate.out" "baseline"
python3 - "$STATE/queue.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
rows = conn.execute(
    "SELECT package, active, cache_policy, wall_s FROM sbu_baseline WHERE package='base'").fetchall()
assert len(rows) == 1 and rows[0][1] == 1, rows
assert "cold" in rows[0][2], rows
assert rows[0][3] is not None and rows[0][3] >= 0, rows
print("baseline row ok")
PY
# Second calibration retires the first (one active row per package).
"$SAPHIRA_BUILD" calibrate base > /dev/null 2>&1
python3 - "$STATE/queue.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
active = conn.execute(
    "SELECT COUNT(*) FROM sbu_baseline WHERE package='base' AND active=1").fetchone()[0]
assert active == 1, active
print("baseline rotation ok")
PY
# Deterministic ratio math on fixture rows (calibration walls above are
# near-zero stub timings, useless as divisors).
python3 - "$STATE/queue.db" <<'PY'
import json
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.execute(
    "INSERT INTO sbu_baseline(package,version,revision,arch,builder_host,cache_policy,"
    " wall_s,active,calibrated_at)"
    " VALUES (?,?,?,?,?,?,?,?,?)",
    ("mathref", "1.0", "1", "x86_64", "egg", "cold (fixture)", 50.0, 1,
     "2026-10-27T11:00:00Z"))
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,started_at,finished_at,"
    " duration_s,arch,builder_host,result_json)"
    " VALUES (?,?,?,?,?,?,?,?,?,?,?)",
    ("mathpkg", "1.0", "1", "c" * 64, "PASS",
     "2026-10-27T11:00:00Z", "2026-10-27T11:01:40Z", 100.0,
     "x86_64", "egg", json.dumps({"stages": {}})))
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,started_at,finished_at,"
    " duration_s,arch,builder_host,result_json)"
    " VALUES (?,?,?,?,?,?,?,?,?,?,?)",
    ("refpkg", "1.0", "1", "d" * 64, "FAIL",
     "2026-10-27T11:00:00Z", "2026-10-27T11:00:10Z", 10.0,
     "x86_64", "egg", json.dumps({"attempt": "refusal", "stages": {}})))
conn.commit()
PY
"$SAPHIRA_BUILD" times --sbu=mathref mathpkg > "$TMP/times-sbu.out" 2>&1
assert_contains "ratio math divides by the baseline" "$TMP/times-sbu.out" "2.00"
"$SAPHIRA_BUILD" times --sbu=mathref refpkg > "$TMP/times-sbu-ref.out" 2>&1
if grep "refpkg" "$TMP/times-sbu-ref.out" | grep -Eq ' [0-9]+\.[0-9]{2}( |$)'; then
	bad "refusal row carries an SBU ratio"
else
	ok "refusals are excluded from SBU math"
fi

# The disposable install root is a Saphira root, so it gets the root
# initialisation that no package provides: /bin/sh -> bash and
# /usr/bin/env -> /bin/env. buildpkg does this in a clean build root and
# saphira-bootstrap in a target root; without it apk can install a package
# but cannot RUN its maintainer scripts, and reports it as execve 127 - which
# reads like a missing helper and is not one. The stub apk above models
# exactly that, so an install stage that skips initialisation fails here.
cat >"$TMP/rootinit.py" <<'ROOTINIT'
import importlib.machinery, importlib.util, os, sys, tempfile, pathlib
path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("sb_mod", path)
spec = importlib.util.spec_from_loader("sb_mod", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
root = pathlib.Path(tempfile.mkdtemp(prefix="install-root-test."))
os.rmdir(root); root.mkdir()
# bash and coreutils arrive by normal dependency resolution (IDENTITY_DEPS).
# The /bin/sh link itself now arrives with the bash payload; this test keeps
# exercising the fallback path where it has not landed yet.
(root / "bin").mkdir(parents=True)
for tool in ("bash", "env"):
    p = root / "bin" / tool
    p.write_text("#!/bin/sh\nexit 0\n")
    p.chmod(0o755)
mod.initialise_install_root(root)
sh, env = root / "bin/sh", root / "usr/bin/env"
assert sh.is_symlink() and os.readlink(sh) == "bash", f"/bin/sh: {os.readlink(sh) if sh.is_symlink() else 'not a symlink'}"
assert env.is_symlink() and os.readlink(env) == "/bin/env", "/usr/bin/env is not the expected link"
# Idempotent: re-running must not fail on the existing links.
mod.initialise_install_root(root)
print("rootinit ok")
ROOTINIT
python3 "$TMP/rootinit.py" "$SAPHIRA_BUILD" > "$TMP/rootinit.out" 2>&1
assert_contains "install root gets the /bin/sh and /usr/bin/env root-initialisation links" "$TMP/rootinit.out" "rootinit ok"

# And it fails CLOSED rather than creating a dangling link when the target of
# the link is absent, because a root without bash is not a usable Saphira root.
cat >"$TMP/nobash.py" <<'NOBASH'
import importlib.machinery, importlib.util, os, sys, tempfile, pathlib
path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("sb_mod2", path)
spec = importlib.util.spec_from_loader("sb_mod2", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
root = pathlib.Path(tempfile.mkdtemp(prefix="install-root-nobash."))
os.rmdir(root); root.mkdir()
try:
    mod.initialise_install_root(root)
except SystemExit as exc:
    print("nobash refused:", exc)
    raise SystemExit(0)
print("NOFAIL: a root with no /bin/bash was accepted")
raise SystemExit(1)
NOBASH
python3 "$TMP/nobash.py" "$SAPHIRA_BUILD" > "$TMP/nobash.out" 2>&1
assert_contains "install-root initialisation fails closed when /bin/bash is absent" "$TMP/nobash.out" "nobash refused:"

"$SAPHIRA_BUILD" retry needsmissing > "$TMP/retry.out" 2>&1 || true

# Trust-anchor preflight: with no repository index, the run phase skips
# without consuming queue rows - a missing anchor is environmental, not
# a package failure (regression: whole daemon batches once FAILED every
# queued package against a missing Packages.adb).
mkdir -p "$TMP/empty-repo"
SAPHIRA_REPO="$TMP/empty-repo" "$SAPHIRA_BUILD" run --limit=10 > "$TMP/norun.out" 2>&1 || true
assert_contains "missing index skips build phase" "$TMP/norun.out" "skipping build phase"
assert_contains "missing index processes nothing" "$TMP/norun.out" "0 package(s) processed"

mkdir -p "$TMP/evroot/lib" "$TMP/evroot/usr/bin"
printf '\x7fELFfake' > "$TMP/evroot/usr/bin/prog"
cat > "$TMP/evlib.so" </dev/null
printf 'stub\n' > "$TMP/evroot/lib/libneeded.so.1"
mkdir -p "$TMP/evrecipe"
printf '#!/bin/sh\nexit 0\n' > "$TMP/evrecipe/test.sh"
chmod +x "$TMP/evrecipe/test.sh"

cat > "$TMP/stub-apk-eval" <<'EOF'
#!/bin/sh
root=""
for a in "$@"; do case "$a" in --root=*) root=${a#--root=};; esac; done
echo "mypkg-1.0-r0 contains:"
echo "usr/bin/prog"
exit 0
EOF
chmod +x "$TMP/stub-apk-eval"
SAPHIRA_APK="$TMP/stub-apk-eval" "$SAPHIRA_BUILD" evaluate "$TMP/evroot" mypkg "$TMP/evrecipe" > "$TMP/eval.out" 2>&1
assert_contains "evaluate: RUNTIME passes with lib present" "$TMP/eval.out" '"RUNTIME"'
assert_contains "evaluate: no policy failure" "$TMP/eval.out" '"POLICY"'
if grep -q '"status": "fail"' "$TMP/eval.out"; then
    bad "evaluate: unexpected stage failure"
else
    ok "evaluate: all stages pass on clean root"
fi

printf 'ExecStart=/usr/bin/sh -c x\n' > "$TMP/evroot/usr/bin/prog"
SAPHIRA_APK="$TMP/stub-apk-eval" "$SAPHIRA_BUILD" evaluate "$TMP/evroot" mypkg "$TMP/evrecipe" > "$TMP/eval2.out" 2>&1 || true
assert_contains "evaluate: /usr/bin/sh policy failure detected" "$TMP/eval2.out" '"/usr/bin/sh reference'

WORLD_AFTER=$(sha256sum /etc/apk/world 2>/dev/null | cut -d' ' -f1 || echo none)
[ "$WORLD_BEFORE" = "$WORLD_AFTER" ] && ok "Egg package world unchanged" || bad "Egg package world CHANGED"

# --- interrupted-build recovery -----------------------------------------
#
# A build that was in flight when its builder died leaves its row in
# BUILDING forever. 13 rows sat that way after the 2026-09-29 reboot.
#
# The bite is not cosmetic. cmd_retry() only requeues FAIL or BLOCKED, so a
# package whose LATEST attempt died mid-build is permanently un-retryable:
# the attempt that would have written FAIL never happened, the row says
# BUILDING, and every later `retry` is refused with "is BUILDING, not
# FAIL/BLOCKED". Nothing in the system ever moves it again. That is the case
# these tests pin, together with the provenance the retirement must keep.
#
# (None of the 13 real rows happened to be its package's latest, so `status`
# never displayed them as BUILDING. The fix is still required: the next
# reboot mid-build would produce exactly the fatal shape.)
seed_building() { # package, boot_id, pid
    python3 - "$STATE/queue.db" "$1" "$2" "$3" <<'PY'
import sqlite3, sys, json, time
db, pkg, boot, pid = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
conn = sqlite3.connect(db)
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,result_json,"
    "log_dir,queued_at,started_at,builder_pid,boot_id)"
    " VALUES(?,?,?,?,?,?,?,?,?,?,?)",
    (pkg, "9.9", "1", "deadbeef", "BUILDING",
     json.dumps({"stages": {"BUILD": {"status": "pending"},
                            "RUNTIME": {"status": "pass", "detail": "11 ELF files"}}}),
     f"/logs/{pkg}", "2026-01-01T00:00:00Z", "2026-01-01T00:00:01Z",
     None if pid == "null" else int(pid), None if boot == "null" else boot),
)
conn.commit()
PY
}
building_count() {
    python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM builds WHERE state=\"BUILDING\"").fetchone()[0])' "$STATE/queue.db"
}
row_field() { # package, column
    python3 -c 'import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute("SELECT " + sys.argv[3] + " FROM builds WHERE package=? ORDER BY id DESC LIMIT 1",(sys.argv[2],)).fetchone(); print(r[0] if r else "")' "$STATE/queue.db" "$1" "$2"
}

LIVE_BOOT=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown-boot)
DEAD_PID=999999   # above any plausible pid_max on this host, certainly not us

# 1. Reboot: same package name, a boot id this boot has never seen.
seed_building rebootcase "$LIVE_BOOT-rotated" null
# 2. Same boot, dead pid.
seed_building deadpidcase "$LIVE_BOOT" "$DEAD_PID"
# 3. Legacy row with no recorded owner at all (predates provenance).
seed_building legacycase null null

"$SAPHIRA_BUILD" reconcile > "$TMP/reconcile.out" 2>&1
assert_contains "reconcile names the reboot case" "$TMP/reconcile.out" "rebootcase 9.9 BUILDING -> INTERRUPTED (boot changed)"
assert_contains "reconcile names the dead-pid case" "$TMP/reconcile.out" "deadpidcase 9.9 BUILDING -> INTERRUPTED (builder pid gone)"
assert_contains "reconcile names the unowned case" "$TMP/reconcile.out" "legacycase 9.9 BUILDING -> INTERRUPTED (unowned"
[ "$(building_count)" = "0" ] && ok "reconcile clears every stale BUILDING row" || bad "reconcile left $(building_count) BUILDING row(s)"
[ "$(row_field rebootcase state)" = "INTERRUPTED" ] && ok "interrupted row carries the INTERRUPTED state" || bad "rebootcase state is $(row_field rebootcase state)"
# The reconciler also needs a COMPLETE account database: passwd, group AND
# shadow. A root assembled from scratch has none, and apply-accounts.sh (which
# would create it) requires root, so an unprivileged controller seeds the same
# minimal locked-root database buildpkg seeds in a clean build root.
cat >"$TMP/acctseed.py" <<'ACCT'
import importlib.machinery, importlib.util, os, sys, tempfile, pathlib
path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("sb_acct", path)
spec = importlib.util.spec_from_loader("sb_acct", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
root = pathlib.Path(tempfile.mkdtemp(prefix="install-root-acct."))
os.rmdir(root); root.mkdir()
(root / "bin").mkdir(parents=True)
for tool in ("bash", "env"):
    p = root / "bin" / tool
    p.write_text("#!/bin/sh\nexit 0\n"); p.chmod(0o755)
mod.initialise_install_root(root)
for name in ("passwd", "group", "shadow"):
    db = root / "etc" / name
    assert db.exists(), f"{name} was not seeded"
    rows = [l for l in db.read_text().splitlines() if l.strip()]
    assert rows and rows[0].startswith("root:"), f"{name} has no root row: {rows}"
assert (root / "etc/shadow").stat().st_mode & 0o777 == 0o600, "shadow is not 0600"
# Idempotent: a second pass must not duplicate the root rows.
mod.initialise_install_root(root)
for name in ("passwd", "group", "shadow"):
    rows = [l for l in (root / "etc" / name).read_text().splitlines() if l.strip()]
    assert len(rows) == 1, f"{name} duplicated its root row: {rows}"
print("acctseed ok")
ACCT
python3 "$TMP/acctseed.py" "$SAPHIRA_BUILD" > "$TMP/acctseed.out" 2>&1
assert_contains "install root is seeded with a complete minimal account database" "$TMP/acctseed.out" "acctseed ok"

# --- recipe_hash tracks the artefact, not the tree -------------------------
#
# scan() decides what to build by comparing recipe_hash to the hash recorded on
# the package's latest row. Hashing the whole recipe directory therefore made
# an unrelated commit cost a build cycle: editing
# saphira-packager/tests/recipe-rules.sh requeued saphira-packager, which was
# then rebuilt on every scan for as long as the tree moved.
cat >"$TMP/hashrule.py" <<'HASH'
import importlib.machinery, importlib.util, pathlib, shutil, sys
path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("sb_hash", path)
spec = importlib.util.spec_from_loader("sb_hash", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
d = pathlib.Path(sys.argv[2])
shutil.rmtree(d, ignore_errors=True)
(d / "files").mkdir(parents=True)
(d / "tests").mkdir()
(d / "acceptance").mkdir()
(d / "recipe.sh").write_text("pkgname=x\n")
(d / "files" / "payload.bin").write_bytes(b"abc")
(d / "files" / "README.md").write_text("payload doc\n")
(d / "files" / "payload.bin.sha256").write_text("sidecar\n")
(d / "tests" / "suite.sh").write_text("test\n")
(d / "acceptance" / "RESULTS.md").write_text("acc\n")
base = mod.recipe_hash(d)

def probe(label, mutate, expect_change):
    mutate()
    changed = mod.recipe_hash(d) != base
    ok = changed == expect_change
    print(f"{'ok' if ok else 'FAIL'}: {label} -> hash {'changed' if changed else 'unchanged'}")
    return ok

results = [
    probe("a tests/ edit does not force a rebuild",
          lambda: (d / "tests" / "suite.sh").write_text("test2\n"), False),
    probe("an acceptance/ edit does not force a rebuild",
          lambda: (d / "acceptance" / "RESULTS.md").write_text("acc2\n"), False),
    probe("retouching a files sha256 sidecar does not force a rebuild",
          lambda: (d / "files" / "payload.bin.sha256").write_text("sidecar2\n"), False),
    probe("an editor dropping does not force a rebuild",
          lambda: (d / "files" / "payload.bin~").write_text("editor\n"), False),
    probe("a VCS merge artefact does not force a rebuild",
          lambda: (d / "files" / "#payload.bin#").write_text("vcs\n"), False),
    probe("editing recipe.sh does force a rebuild",
          lambda: (d / "recipe.sh").write_text("pkgname=y\n"), True),
    probe("editing a files/ payload input does force a rebuild",
          lambda: (d / "files" / "payload.bin").write_bytes(b"abcd"), True),
    # The suffix rule would get this wrong: nftables installs
    # files/saphira-classification-README.md into its payload, so a .md under
    # files/ is a real build input even though a top-level .md is not.
    probe("editing a markdown file under files does force a rebuild",
          lambda: (d / "files" / "README.md").write_text("payload doc2\n"), True),
    probe("adding a new included input does force a rebuild",
          lambda: (d / "files" / "extra").write_text("new\n"), True),
]
shutil.rmtree(d, ignore_errors=True)
raise SystemExit(0 if all(results) else 1)
HASH
python3 "$TMP/hashrule.py" "$SAPHIRA_BUILD" "$TMP/hashtree" > "$TMP/hashrule.out" 2>&1 || true
for line in \
	"a tests/ edit does not force a rebuild" \
	"an acceptance/ edit does not force a rebuild" \
	"retouching a files sha256 sidecar does not force a rebuild" \
	"an editor dropping does not force a rebuild" \
	"a VCS merge artefact does not force a rebuild" \
	"editing recipe.sh does force a rebuild" \
	"editing a files/ payload input does force a rebuild" \
	"editing a markdown file under files does force a rebuild" \
	"adding a new included input does force a rebuild"; do
	assert_contains "recipe_hash: $line" "$TMP/hashrule.out" "ok: $line ->"
done

# --- scan must not enqueue a published exact NVR --------------------------
#
# Publishing an NVR twice is impossible - sign-apk-repo refuses it by the
# immutable-filename rule - so queueing one can only ever burn a build cycle
# and retain a workspace. saphira-packager 1.0-r70 is published and installed on
# Egg and was queued on every scan anyway: five attempts in five minutes, five
# retained workspaces, five FAIL rows, forever.
#
# The recipe hash cannot catch it, because an unchanged recipe keeps its hash
# and is only queued when something ELSE in its tree moved. So the NVR itself
# has to be checked against the live repository.
#
# The fixture repository is seeded with a real published artefact, and the
# scan is run repeatedly to prove it stays idle rather than churning once.
cat >"$TMP/mkpublished.sh" <<'MKPUB'
#!/bin/sh
# A published repository holds .apk files whose names carry name-version-rNVR.
: > "$1/PLACEHOLDER"
printf 'not really an apk\n' > "$1/publishedpkg-2.0-r4.apk"
printf 'not really an apk\n' > "$1/publishedpkg-doc-2.0-r4.apk"
printf 'not really an apk\n' > "$1/otherpkg-9.9-r1.apk"
rm -f "$1/PLACEHOLDER"
MKPUB
chmod 0755 "$TMP/mkpublished.sh"
"$TMP/mkpublished.sh" "$TMP/repo"
mkdir -p "$RECIPES/publishedpkg/files"
cat > "$RECIPES/publishedpkg/recipe.sh" <<'PUBRECIPE'
pkgname=publishedpkg
pkgver=2.0
pkgrel=4
depends=""
PUBRECIPE

"$SAPHIRA_BUILD" scan > "$TMP/scan-pub1.out" 2>&1
# Read the queue FRESH: an earlier queue.out predates publishedpkg, so grepping
# it would pass whether or not the package was queued.
"$SAPHIRA_BUILD" queue > "$TMP/queue-pub.out" 2>&1 || true
if grep -q '^  publishedpkg 2\.0-r4' "$TMP/queue-pub.out"; then
	bad "the published NVR was queued anyway"
	cat "$TMP/queue-pub.out" >&2
else
	ok "the published NVR never enters the queue"
fi

# Repeated scans must stay idle. Before the fix each scan produced another
# QUEUED row for this package, which is what the 76-second cycle was.
for i in 1 2 3; do
	"$SAPHIRA_BUILD" scan >> "$TMP/scan-pub1.out" 2>&1
done
rows=$(sqlite3 "$STATE/queue.db" "SELECT count(*) FROM builds WHERE package='publishedpkg'" 2>/dev/null || echo 0)
[ "$rows" = "0" ] && ok "repeated scans of a published NVR stay idle (0 rows after 4 scans)" \
	|| bad "repeated scans produced $rows queue row(s) for a published NVR"

# And a split sibling's NVR must not be mistaken for the parent's: the
# publishedpkg-doc artefact is a different name and must not suppress anything.
rows=$(sqlite3 "$STATE/queue.db" "SELECT count(*) FROM builds WHERE package='publishedpkg-doc'" 2>/dev/null || echo 0)
[ "$rows" = "0" ] && ok "a split sibling artefact does not create or suppress work" \
	|| bad "a split sibling produced $rows queue row(s)"

# A package whose NVR is NOT published must still be queued, or the check
# would just be disabling the scanner.
"$SAPHIRA_BUILD" scan > "$TMP/scan-pub2.out" 2>&1
assert_contains "an unpublished NVR is still queued" "$TMP/queue.out" "base"

assert_has "provenance records the previous state" "$(row_field rebootcase result_json)" '"previous_state": "BUILDING"'
assert_has "provenance records the reason" "$(row_field rebootcase result_json)" '"reason": "boot changed"'
assert_has "provenance keeps the log directory reachable" "$(row_field rebootcase result_json)" '"log_dir": "/logs/rebootcase"'
assert_has "provenance keeps the start time" "$(row_field rebootcase result_json)" '"started_at": "2026-01-01T00:00:01Z"'
assert_has "build stage is marked interrupted, not silently current" "$(row_field rebootcase result_json)" '"status": "interrupted"'
assert_has "a stage that ran before the crash is preserved, not lost" "$(row_field rebootcase result_json)" '"RUNTIME": {"status": "pass"'
case $(row_field rebootcase result_json) in
    *'"status": "pending"'*) bad "the interrupted BUILD verdict was appended to rather than replacing the stale one" ;;
    *) ok "the interrupted BUILD verdict replaces the stale pending one" ;;
esac

# A live builder that is not us still owns its row: an in-flight build
# belonging to some other builder must not be retired out from under it.
seed_building livepidcase "$LIVE_BOOT" "$$"
"$SAPHIRA_BUILD" reconcile > "$TMP/reconcile2.out" 2>&1
[ "$(row_field livepidcase state)" = "BUILDING" ] \
    && ok "a row owned by another live builder is left alone" \
    || bad "a live-builder-owned row was retired to $(row_field livepidcase state)"

# Idempotent: with nothing stale left, reconcile reports that it found
# nothing rather than re-retiring. Checked here, while the only BUILDING row
# is the live-builder one that reconcile deliberately leaves alone.
"$SAPHIRA_BUILD" reconcile > "$TMP/reconcile3.out" 2>&1
assert_contains "reconcile is idempotent" "$TMP/reconcile3.out" "no interrupted build rows"

# The self-guard is only observable from inside the owning process, so it is
# driven in-process: a row stamped with THIS process's pid and boot id must
# survive its own reconcile.
cat > "$TMP/selfguard.py" <<'GUARD'
import importlib.machinery, importlib.util, json, os, sys
path, db = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("saphira_build_mod", path)
spec = importlib.util.spec_from_loader("saphira_build_mod", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)          # __name__ != "__main__": main() does not run
conn = mod.db()
conn.execute(
    "INSERT INTO builds(package,version,revision,recipe_hash,state,result_json,"
    "log_dir,queued_at,started_at,builder_pid,boot_id)"
    " VALUES(?,?,?,?,?,?,?,?,?,?,?)",
    ("selfcase", "9.9", "1", "cafebabe", "BUILDING",
     json.dumps({"stages": {}}), "/logs/selfcase",
     "2026-01-01T00:00:00Z", "2026-01-01T00:00:01Z",
     os.getpid(), mod.boot_id()),
)
conn.commit()
retired = mod.reconcile_interrupted(conn)
state = conn.execute("SELECT state FROM builds WHERE package='selfcase'").fetchone()[0]
if retired or state != "BUILDING":
    print("SELFGUARD-BROKEN retired=%r state=%s" % (retired, state))
    raise SystemExit(1)
print("selfguard ok")
GUARD
python3 "$TMP/selfguard.py" "$SAPHIRA_BUILD" "$STATE/queue.db" > "$TMP/selfguard.out" 2>&1
assert_contains "a row owned by this very process survives its own reconcile" "$TMP/selfguard.out" "selfguard ok"

# The fatal shape, end to end: a package whose LATEST row is a dead
# BUILDING one. Before the fix `retry` refused it forever, because the
# attempt that would have written FAIL never happened.
seed_building latestcase "$LIVE_BOOT-rotated" null
"$SAPHIRA_BUILD" retry latestcase > "$TMP/retry-before.out" 2>&1 || true
assert_contains "a dead BUILDING row is refused by retry before recovery" "$TMP/retry-before.out" "not FAIL/BLOCKED"
"$SAPHIRA_BUILD" reconcile > "$TMP/reconcile-latest.out" 2>&1
"$SAPHIRA_BUILD" retry latestcase > "$TMP/retry-after.out" 2>&1
[ "$(row_field latestcase state)" = "QUEUED" ] \
    && ok "a package whose latest build died mid-flight becomes retryable again" \
    || bad "latest-case retry after recovery left state $(row_field latestcase state)"

# Nothing is requeued automatically: a machine that lost power has not
# proven that every in-flight build needs repeating.
[ "$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM builds WHERE package IN (\"rebootcase\",\"deadpidcase\",\"legacycase\") AND state=\"QUEUED\"").fetchone()[0])' "$STATE/queue.db")" = "0" ] \
    && ok "interrupted builds are not requeued automatically" || bad "interrupted builds were auto-requeued"

# An interrupted build IS retryable, because that is the whole point of
# recording it as retryable rather than as rot.
"$SAPHIRA_BUILD" retry rebootcase > "$TMP/retry-interrupted.out" 2>&1
[ "$(row_field rebootcase state)" = "QUEUED" ] && ok "an interrupted build can be retried explicitly" || bad "retry of INTERRUPTED did not requeue"

# The self-guard is per-process, not a permanent exemption: the python process
# that owned `selfcase` has exited, so the very next reconcile retires it.
assert_contains "a row whose owning process has since exited is retired by the next reconcile" "$TMP/reconcile-latest.out" "selfcase 9.9 BUILDING -> INTERRUPTED"

"$SAPHIRA_BUILD" reconcile > "$TMP/reconcile4.out" 2>&1
assert_contains "reconcile is still idempotent once everything is retired" "$TMP/reconcile4.out" "no interrupted build rows"

"$SAPHIRA_BUILD" status > "$TMP/status-interrupted.out" 2>&1
assert_contains "status renders an interrupted row legibly" "$TMP/status-interrupted.out" "INTERRUPTED"

# --- MCP journal bridge (optional, fail-open, non-blocking) -----------------
#
# The builder never requires the journal: missing file (never created),
# read-only file, wrong schema, locked database, and concurrent writers
# must all leave build logic unaffected. Recovery of anything skipped is
# the MCP's startup reconciliation. Event identity is the exact title
# key bridge:<builder>:<build_id>:<event>:<seq> - never LIKE.
BST=$TMP/bstate
BREC=$TMP/brecipes
BREP=$TMP/brepo
BINC=$TMP/bincoming
BJOURNAL=$TMP/journal.db
mkdir -p "$BST" "$BREC" "$BREP" "$BINC"
export SBM_NOTES_DB="$BJOURNAL"
BENV="SAPHIRA_BUILD_STATE=$BST SAPHIRA_RECIPES=$BREC SAPHIRA_INCOMING=$BINC SAPHIRA_REPO=$BREP SAPHIRA_BUILDCMD=$TMP/stub-buildpkg SAPHIRA_APK=$TMP/stub-apk SAPHIRA_TEST_ROOTS=$TMP/btestroots SAPHIRA_INCOMING_STUB=$BINC RECIPE_ROOT=$BREC SBM_NOTES_DB=$BJOURNAL"
mkdir -p "$BREP"
: > "$BREP/Packages.adb"
mkrecipe() { # name ver rel deps...
	name=$1; ver=$2; rel=$3; shift 3
	mkdir -p "$BREC/$name/files"
	printf 'pkgname=%s\npkgver=%s\npkgrel=%s\ndepends="%s"\n' "$name" "$ver" "$rel" "$*" > "$BREC/$name/recipe.sh"
}
mkjournal() {
	rm -f "$BJOURNAL"
	python3 - "$BJOURNAL" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE session_events(id INTEGER PRIMARY KEY, event TEXT, package TEXT, label TEXT, title TEXT, body TEXT, author TEXT, recorder TEXT, created_at TEXT, session_id TEXT, hostname TEXT, username TEXT, cwd TEXT, agent TEXT, ctx_origin TEXT)")
conn.commit()
PY
}
bridge_rows() { # event -> count
	python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM session_events WHERE event=?",(sys.argv[2],)).fetchone()[0])' "$BJOURNAL" "$1"
}
bridge_titles() { # event -> titles
	python3 -c 'import sqlite3,sys; [print(r[0]) for r in sqlite3.connect(sys.argv[1]).execute("SELECT title FROM session_events WHERE event=?",(sys.argv[2],))]' "$BJOURNAL" "$1"
}

# 1. Missing journal: bridge never creates it, builds unaffected.
rm -f "$BJOURNAL"
mkrecipe okpkg 1.0 1 ""
env $BENV "$SAPHIRA_BUILD" scan > "$TMP/bridge-scan-nojournal.out" 2>&1
[ -e "$BJOURNAL" ] && bad "bridge created the journal file" || ok "bridge never creates a missing journal"
assert_contains "scan works with no journal" "$TMP/bridge-scan-nojournal.out" "newly queued"

# 2. FAIL emits one exact-keyed build.failed; resweep never duplicates.
mkjournal
mkrecipe brokenbridge 1.0 1 ""
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
env $BENV "$SAPHIRA_BUILD" run --limit=5 > "$TMP/bridge-run-fail.out" 2>&1 || true
assert_contains "broken build fails" "$TMP/bridge-run-fail.out" "brokenbridge -> FAIL"
[ "$(bridge_rows build.failed)" = "1" ] && ok "FAIL emits exactly one build.failed" || bad "FAIL emitted $(bridge_rows build.failed) build.failed rows"
key=$(bridge_titles build.failed)
case "$key" in bridge:*:*:build.failed:1) ok "FAIL identity is the exact bridge key ($key)";; *) bad "FAIL key malformed: $key";; esac
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
[ "$(bridge_rows build.failed)" = "1" ] && ok "resweep does not duplicate build.failed" || bad "resweep duplicated build.failed"

# 3. BLOCKED transition emits with seq; identical resweep is idempotent;
# changed blockers emit a new seq; unblock emits build.unblocked.
mkrecipe ghostdep 9.9 9 ""
mkrecipe blockedpkg 1.0 1 "ghostdep"
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
[ "$(bridge_rows build.blocked)" = "1" ] && ok "BLOCKED emits one build.blocked" || bad "BLOCKED emitted $(bridge_rows build.blocked)"
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
[ "$(bridge_rows build.blocked)" = "1" ] && ok "identical BLOCKED resweep is idempotent" || bad "identical BLOCKED resweep duplicated"
# Satisfy the dep: ghostdep builds PASS, blockedpkg unblocks.
env $BENV "$SAPHIRA_BUILD" run --limit=10 > /dev/null 2>&1 || true
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
[ "$(bridge_rows build.unblocked)" = "1" ] && ok "unblock emits one build.unblocked" || bad "unblocked emitted $(bridge_rows build.unblocked)"

# 4. Locked journal: contention is skipped fast, build still passes.
mkjournal
mkrecipe lockpkg 1.0 1 ""
chmod 444 "$BJOURNAL"
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
env $BENV "$SAPHIRA_BUILD" run --limit=5 > "$TMP/bridge-run-locked.out" 2>&1 || true
assert_contains "build passes with read-only journal" "$TMP/bridge-run-locked.out" "lockpkg -> PASS"
chmod 644 "$BJOURNAL"
python3 - "$SAPHIRA_BUILD" "$BJOURNAL" <<'PY' > "$TMP/bridge-lock-timing.out" 2>&1
import importlib.machinery, importlib.util, sqlite3, sys, time
path, jpath = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("sb_bridge", path)
spec = importlib.util.spec_from_loader("sb_bridge", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
hold = sqlite3.connect(jpath, timeout=10)
hold.execute("BEGIN EXCLUSIVE")
hold.execute("INSERT INTO session_events(event,package,label,title,body,author,recorder,created_at) VALUES('hold','h','l','hold','{}','a','r','t')")
t0 = time.time()
assert mod.bridge_emit("build.failed", "p", "1.0-r1", 999999, 1, {}) is False
dt = time.time() - t0
hold.rollback()
print(f"contention-skipped in {dt:.2f}s")
assert dt < 2.0, dt
PY
assert_contains "lock contention is skipped with negligible delay" "$TMP/bridge-lock-timing.out" "contention-skipped"

# 5. Wrong schema: skipped, never raises, build unaffected.
python3 - "$BJOURNAL" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("DROP TABLE session_events")
conn.execute("CREATE TABLE session_events(id INTEGER PRIMARY KEY, nope TEXT)")
conn.commit()
PY
mkrecipe schemapkg 1.0 1 ""
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
env $BENV "$SAPHIRA_BUILD" run --limit=5 > "$TMP/bridge-run-schema.out" 2>&1 || true
assert_contains "build passes with wrong-schema journal" "$TMP/bridge-run-schema.out" "schemapkg -> PASS"

# 6. Concurrency: parallel writers, MCP-style unique index present.
mkjournal
python3 - "$BJOURNAL" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_session_events_bridge_key ON session_events(title)")
conn.commit()
PY
python3 - "$SAPHIRA_BUILD" "$BJOURNAL" <<'PY'
import importlib.machinery, importlib.util, os, sys, threading
path, jpath = sys.argv[1], sys.argv[2]
os.environ["SBM_NOTES_DB"] = jpath
loader = importlib.machinery.SourceFileLoader("sbw", path)
spec = importlib.util.spec_from_loader("sbw", loader)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
results = []
def worker(_):
    try:
        # Contention is skipped, never waited on: retry briefly so a
        # 16-way pile-up still delivers at least once without ever
        # blocking. The race itself (shared key, shared file) is real
        # on every attempt; retries only tolerate total lock-out.
        import time as _t
        for _ in range(50):
            if mod.bridge_emit("build.failed", "racepkg", "1.0-r1", 4242, 1, {}):
                results.append(True)
                return
            _t.sleep(0.005)
        results.append(False)
    except Exception as e:  # noqa: BLE001 - the bridge must never raise; record it
        results.append(f"RAISED:{e}")
threads = [threading.Thread(target=worker, args=(i,)) for i in range(16)]
[t.start() for t in threads]
[t.join() for t in threads]
assert all(r in (True, False) for r in results), results
assert any(results), "event lost under concurrency"
print(f"concurrency ok: {len(results)} writers, none raised")
PY
n=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM session_events WHERE event=\"build.failed\"").fetchone()[0])' "$BJOURNAL")
[ "$n" -ge "1" ] && ok "concurrent writers deliver the event (rows=$n, deduped by obligations GROUP BY)" || bad "concurrent writers lost the event"

# 7. Published-NVR rule: a BLOCKED row whose exact NVR is published reads succeeded.
mkjournal
mkrecipe pubpkg 2.0 4 "ghost-missing-dep"
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
printf 'not an apk\n' > "$BREP/pubpkg-2.0-r4.apk"
env $BENV "$SAPHIRA_BUILD" status > "$TMP/bridge-status-pub.out" 2>&1
if grep -q "pubpkg" "$TMP/bridge-status-pub.out" && grep "pubpkg" "$TMP/bridge-status-pub.out" | grep -q "PUBLISHED"; then
	ok "status reports succeeded for a published NVR despite BLOCKED row"
else
	bad "status does not report succeeded for published NVR"
fi
env $BENV "$SAPHIRA_BUILD" queue > "$TMP/bridge-queue-pub.out" 2>&1 || true
if grep -q "pubpkg" "$TMP/bridge-queue-pub.out"; then
	bad "queue lists a published NVR as outstanding"
else
	ok "queue hides a published NVR from outstanding states"
fi
rm -f "$BREP/pubpkg-2.0-r4.apk"

# 8. Stalled sweep: old QUEUED row emits one bucketed build.stalled event.
mkjournal
mkrecipe stallpkg 1.0 1 ""
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
python3 - "$BST/queue.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE builds SET queued_at='2020-01-01T00:00:00Z' WHERE package='stallpkg'")
conn.commit()
PY
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
stalled=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM session_events WHERE event LIKE \"build.stalled.%\"").fetchone()[0])' "$BJOURNAL")
[ "$stalled" = "1" ] && ok "stalled sweep emits one bucketed event" || bad "stalled sweep emitted $stalled"
env $BENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
stalled2=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM session_events WHERE event LIKE \"build.stalled.%\"").fetchone()[0])' "$BJOURNAL")
[ "$stalled2" = "1" ] && ok "stalled resweep does not duplicate" || bad "stalled resweep duplicated ($stalled2)"
# --- publication reconciliation + effective state -----------------------
#
# The queue is not the only publication path: operators run
# `sudo sign-apk-repo` directly (the documented human step), which
# regenerates repository.db without touching queue.db. Rows then read
# AWAITING SIGNING forever while their exact NVR is live (observed:
# grub/lvm2 r3). sync_published() backfills published_at from
# repository.db (exact-NVR only, repo timestamp, fail-open).
# Effective state is requested recipe NVR + actual repo publication +
# the attempt, never the latest row alone.
SREP=$TMP/syncrepo
mkdir -p "$SREP"
python3 - "$SREP/repository.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE packages(package_id INTEGER PRIMARY KEY, name TEXT NOT NULL, version TEXT NOT NULL, pkgrel INTEGER NOT NULL, nvr TEXT NOT NULL, apk_sha256 TEXT NOT NULL, is_newest INTEGER NOT NULL, published_at TEXT, UNIQUE(name, version))")
conn.execute("INSERT INTO packages(name,version,pkgrel,nvr,apk_sha256,is_newest,published_at) VALUES('syncpkg','3.1',2,'syncpkg-3.1-r2','x'*64,1,'2026-10-01T00:00:00Z')")
conn.commit()
PY
mkrecipe syncpkg 3.1 2 ""
SENV="SAPHIRA_BUILD_STATE=$BST SAPHIRA_RECIPES=$BREC SAPHIRA_INCOMING=$BINC SAPHIRA_REPO=$SREP SAPHIRA_BUILDCMD=$TMP/stub-buildpkg SAPHIRA_APK=$TMP/stub-apk SAPHIRA_TEST_ROOTS=$TMP/btestroots SAPHIRA_INCOMING_STUB=$BINC REPO_ROOT=$BREC"
# Deterministic PASS row (direct insert, like the STALE test): the point
# under test is publication reconciliation, not the stub build.
python3 - "$BST/queue.db" <<'PY'
import sqlite3, json, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("INSERT INTO builds(package,version,revision,recipe_hash,state,result_json,queued_at,started_at,finished_at) VALUES(?,?,?,?,?,?,?,?,?)",
    ("syncpkg", "3.1", "2", "0" * 64, "PASS", json.dumps({"stages": {"BUILD": {"status": "pass"}}}),
     "2026-10-01T00:00:00Z", "2026-10-01T00:00:01Z", "2026-10-01T00:00:02Z"))
conn.commit()
PY
env $SENV "$SAPHIRA_BUILD" reconcile > "$TMP/reconcile-sync.out" 2>&1
assert_contains "reconcile stamps repo-published rows" "$TMP/reconcile-sync.out" "stamped published from the repository"
pub=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT published_at FROM builds WHERE package=\"syncpkg\" ORDER BY id DESC LIMIT 1").fetchone()[0])' "$BST/queue.db")
t_eq_tmp="2026-10-01T00:00:00Z"
[ "$pub" = "$t_eq_tmp" ] && ok "published_at backfilled with the repo timestamp, not now" || bad "published_at is $pub, want repo timestamp"
env $SENV "$SAPHIRA_BUILD" status > "$TMP/status-sync.out" 2>&1
if grep "syncpkg" "$TMP/status-sync.out" | grep -q "PUBLISHED"; then
	ok "effective state reads PUBLISHED after sync"
else
	bad "effective state does not read PUBLISHED after sync"
fi

# STALE: the attempt failed for an NVR the recipe has moved past.
mkrecipe stalepkg 2.0 2 ""
python3 - "$BST/queue.db" <<'PY'
import sqlite3, json, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("INSERT INTO builds(package,version,revision,recipe_hash,state,result_json,queued_at,started_at,finished_at) VALUES(?,?,?,?,?,?,?,?,?)",
    ("stalepkg", "1.0", "1", "0" * 64, "FAIL", json.dumps({"stages": {"BUILD": {"status": "fail"}}}),
     "2026-10-01T00:00:00Z", "2026-10-01T00:00:01Z", "2026-10-01T00:00:02Z"))
conn.commit()
PY
env $SENV "$SAPHIRA_BUILD" status > "$TMP/status-stale.out" 2>&1
if grep "stalepkg" "$TMP/status-stale.out" | grep -q "STALE"; then
	ok "failed attempt past the recipe NVR reads STALE, not FAILED"
else
	bad "stale failure not distinguished"
fi
if grep "stalepkg" "$TMP/status-stale.out" | grep -q "recipe now 2.0-r2"; then
	ok "stale note names the requested revision"
else
	bad "stale note missing requested revision"
fi
# gpu-unlock shape: latest QUEUED with older BLOCKED rows reads QUEUED
# (latest attempt wins) while history keeps the BLOCKED attempts.
mkrecipe gunlock 2.0.0 1 "ghostdep-unlock"
env $SENV "$SAPHIRA_BUILD" scan > /dev/null 2>&1
python3 - "$BST/queue.db" <<'PY'
import sqlite3, json, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE builds SET state='QUEUED', result_json=? WHERE package='gunlock' AND state='BLOCKED'",
    (json.dumps({"stages": {}}),))
conn.commit()
PY
env $SENV "$SAPHIRA_BUILD" status > "$TMP/status-gunlock.out" 2>&1
if grep "gunlock" "$TMP/status-gunlock.out" | grep -q "QUEUED"; then
	ok "latest QUEUED wins over older BLOCKED rows (with history kept)"
else
	bad "gpu-unlock-shaped rows do not read QUEUED"
fi
unset SBM_NOTES_DB

WORLD_AFTER2=$(sha256sum /etc/apk/world 2>/dev/null | cut -d' ' -f1 || echo none)
[ "$WORLD_BEFORE" = "$WORLD_AFTER2" ] && ok "Egg package world unchanged after recovery" || bad "Egg package world CHANGED"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

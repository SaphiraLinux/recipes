#!/bin/sh

# withdraw-package.sh: hermetic test for withdraw-package (explicit
# package-family withdrawal) and the withdrawals audit table.
#
# - withdrawal removes every indexed NVR of a family, newest included
# - live dependents refuse the withdrawal without mutating anything
# - withdrawn APKs land in the archive byte-identical (hash-pinned)
# - one audit row per NVR records hash/size/count/actor/reason/time
# - ACTIVE reservations owned by the family are tombstoned, never deleted
# - re-withdrawal is a verified no-op; unknown families refuse
# - a stranded run (marker set, files moved, rows present) refuses with
#   a restore-and-heal pointer instead of guessing
# - a later --full-audit heal keeps the audit rows (evidence survives)
#
# usage: withdraw-package.sh WITHDRAW-PACKAGE SIGN-APK-REPO MAKEPKG

set -eu

withdraw=${1:-}
sign_repo=${2:-}
makepkg=${3:-}
[ -n "$withdraw" ] && [ -n "$sign_repo" ] && [ -n "$makepkg" ] || {
	printf 'usage: %s WITHDRAW-PACKAGE SIGN-APK-REPO MAKEPKG\n' "$0" >&2
	exit 2
}
command -v unshare >/dev/null 2>&1 || { printf 'unshare missing, skipping\n'; exit 0; }
command -v openssl >/dev/null 2>&1 || { printf 'openssl missing, skipping\n'; exit 0; }

source_root=$(CDPATH= cd -- "$(dirname -- "$withdraw")/../.." && pwd)
test_root=$(mktemp -d "${SAPHIRA_TMPDIR:-/build/tmp}/withdraw-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/repo" "$test_root/incoming" "$test_root/archive" \
	"$test_root/stage" "$test_root/artifacts" "$test_root/keys" \
	"$test_root/recipes"
# The publisher resolves every staged transaction's producing recipe
# (skipping disabled ones, refusing unknown ones). Real builder
# transactions always name an existing recipe, so the fixtures do
# too: stage_auth_txn below auto-creates a minimal enabled stub for
# each producer. Tests that need a disabled or missing recipe write
# (or omit) the stub explicitly.
export SAPHIRA_RECIPE_ROOT="$test_root/recipes"
repo=$test_root/repo/hatchling/x86_64
incoming=$test_root/incoming/x86_64
mkdir -p "$repo" "$incoming"
openssl genrsa -traditional -out "$test_root/test-repository.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$test_root/test-repository.rsa" -pubout \
	-out "$test_root/keys/test-repository.rsa.pub" >/dev/null 2>&1
keys=$test_root/keys

init_repo_db()
{
	python3 - "$source_root/saphira-packager/files/repo_db.py" "$1" "$2" <<'PY'
import os
import sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import repo_db
conn = repo_db.connect(os.path.join(sys.argv[2], "repository.db"))
repo_db.init_db(conn, sys.argv[3], True)
conn.commit()
conn.close()
PY
}
init_repo_db "$repo" hatchling

run_signer()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repo SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}

run_withdraw()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repo SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$withdraw" "$@"
}

db_query()
{
	python3 - "$test_root/repo/hatchling/x86_64/repository.db" "$1" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
conn.row_factory = sqlite3.Row
print(conn.execute(sys.argv[2]).fetchone()[0])
PY
}

stage=$test_root/stage
artifacts=$test_root/artifacts
mkpkg()
{
	name=$1 version=$2
	deps=${3:-}
	rm -rf "$stage/$name"
	mkdir -p "$stage/$name/pkg/usr/bin"
	printf '%s\n' "$name" > "$stage/$name/pkg/usr/bin/$name"
	printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"'$name'","origin":"'$name'","outputs":[{"dependencies":['$deps'],"description":"'$name'","name":"'$name'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"'$version'"}' > "$stage/$name/manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$name" >/dev/null
}

stage_auth_txn()
{
	txn=$1 target=$2 producer=$3
	shift 3
	apk1=$1
	ver=${apk1#$producer-}
	ver=${ver%.apk}
	if [ ! -f "$SAPHIRA_RECIPE_ROOT/$producer/recipe.sh" ]; then
		mkdir -p "$SAPHIRA_RECIPE_ROOT/$producer"
		printf '%s\n' "pkgname=$producer" > "$SAPHIRA_RECIPE_ROOT/$producer/recipe.sh"
	fi
	mkdir "$txn"
	for apk in "$@"; do
		cp "$artifacts/x86_64/$apk" "$txn/"
	done
	printf '%s\n' "$target" > "$txn/target"
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$txn/package-seed.json"
	apksha=$(sha256sum "$txn/$apk1" | awk '{ print $1 }')
	printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"'$producer'","constructors":[{"constructor":"makepkg","producer":"'$producer'","artifacts":[{"name":"'$producer'","artifact":"'$apk1'","sha256":"'$apksha'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$txn/artifact-manifest.json"
	printf '%s\n' '{"arch":"x86_64","builds":[{"build_dependencies":[],"outputs":["'$producer'"],"producer":"'$producer'","recipe":"test","required_outputs":["'$producer'"],"target":true,"version":"'$ver'"}],"repository":[],"schema":"saphira-build-plan/v1","target":"'$producer'","target_producer":"'$producer'"}' > "$txn/plan.json"
	printf '%s\n' '{"local":[{"artifacts":[{"artifact":"'$apk1'","name":"'$producer'","sha256":"'$apksha'"}],"producer":"'$producer'","target":true,"version":"'$ver'"}],"repository":[],"schema":"saphira-build-closure/v1","target":"'$producer'","target_producer":"'$producer'"}' > "$txn/closure-hashes.json"
	(CDPATH= cd -- "$txn" && sha256sum "$@" > manifest.sha256)
}

# --- seed: family fam-a (two NVRs) plus a live dependent dep-d ---
mkpkg fam-a 1-r1
mkpkg fam-a 2-r1
mkpkg dep-d 1-r1 '"fam-a"'
mkpkg keeper 1-r1
stage_auth_txn "$incoming/fama1-ready" fam-a fam-a fam-a-1-r1.apk
stage_auth_txn "$incoming/fama2-ready" fam-a fam-a fam-a-2-r1.apk
stage_auth_txn "$incoming/depd-ready" dep-d dep-d dep-d-1-r1.apk
stage_auth_txn "$incoming/keeper-ready" keeper keeper keeper-1-r1.apk
run_signer > "$test_root/seed.out" 2> "$test_root/seed.err"
test -f "$repo/fam-a-1-r1.apk"
test -f "$repo/fam-a-2-r1.apk"
test -f "$repo/dep-d-1-r1.apk"
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-a'")" = 2 ]
printf '%s\n' 'seed publish: OK'

# --- 1. live dependent refuses without mutating ---
before=$(find "$repo" -type f -printf '%P %s\n' | sort | sha256sum)
if run_withdraw fam-a --reason 'retired upstream' > "$test_root/ref.out" 2> "$test_root/ref.err"; then
	printf '%s\n' 'withdrawal with live dependent unexpectedly succeeded' >&2
	exit 1
fi
grep -E 'live dependents refuse|dep-d' "$test_root/ref.err" >/dev/null
[ "$before" = "$(find "$repo" -type f -printf '%P %s\n' | sort | sha256sum)" ]
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-a'")" = 2 ]
[ "$(db_query 'SELECT COUNT(*) FROM withdrawals')" = 0 ]
[ "$(db_query "SELECT COUNT(*) FROM metadata WHERE key='withdrawal_pending'")" = 0 ]
printf '%s\n' 'dependent refusal without mutation: OK'

# --- 2. plant an ACTIVE reservation, withdraw the dependent first ---
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1], timeout=30.0, isolation_level=None)
conn.execute("INSERT INTO reservations(kind, name, numeric_id, owning_package,"
             " first_nvr, last_nvr, status, declaration_sha256)"
             " VALUES ('user', 'famuser', 501, 'fam-a',"
             " 'fam-a-1-r1', 'fam-a-2-r1', 'ACTIVE', 'test')")
conn.commit()
PY
run_withdraw dep-d --reason 'retired upstream' --archive-dir "$test_root/archive" \
	> "$test_root/wd.out" 2> "$test_root/wd.err"
test ! -e "$repo/dep-d-1-r1.apk"
test -f "$test_root/archive/dep-d/dep-d-1-r1.apk"
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='dep-d'")" = 0 ]
[ "$(db_query "SELECT COUNT(*) FROM withdrawals WHERE name='dep-d'")" = 1 ]
if apk adbdump "$repo/Packages.adb" | grep -q 'name: dep-d'; then
	printf '%s\n' 'dep-d still indexed' >&2; exit 1
fi
printf '%s\n' 'dependent withdrawal: OK'

# --- 3. withdraw the family (newest included): rows go, audit stays ---
fam1_sha=$(sha256sum "$repo/fam-a-1-r1.apk" | awk '{ print $1 }')
fam2_sha=$(sha256sum "$repo/fam-a-2-r1.apk" | awk '{ print $1 }')
run_withdraw fam-a --reason 'retired upstream' --archive-dir "$test_root/archive" \
	> "$test_root/wfam.out" 2> "$test_root/wfam.err"
test ! -e "$repo/fam-a-1-r1.apk"
test ! -e "$repo/fam-a-2-r1.apk"
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-a'")" = 0 ]
[ "$(db_query 'SELECT COUNT(*) FROM files WHERE package_id NOT IN (SELECT package_id FROM packages)')" = 0 ]
[ "$(db_query "SELECT COUNT(*) FROM withdrawals WHERE name='fam-a'")" = 2 ]
[ "$(db_query "SELECT apk_sha256 FROM withdrawals WHERE nvr='fam-a-1-r1'")" = "$fam1_sha" ]
[ "$(db_query "SELECT apk_sha256 FROM withdrawals WHERE nvr='fam-a-2-r1'")" = "$fam2_sha" ]
[ "$(db_query "SELECT withdrawn_by FROM withdrawals WHERE nvr='fam-a-1-r1'")" = root ]
[ "$(db_query "SELECT reason FROM withdrawals WHERE nvr='fam-a-1-r1'")" = 'retired upstream' ]
[ "$(db_query "SELECT COUNT(*) FROM metadata WHERE key='withdrawal_pending'")" = 0 ]
[ "$(sha256sum "$test_root/archive/fam-a/fam-a-1-r1.apk" | awk '{ print $1 }')" = "$fam1_sha" ]
[ "$(sha256sum "$test_root/archive/fam-a/fam-a-2-r1.apk" | awk '{ print $1 }')" = "$fam2_sha" ]
[ "$(db_query "SELECT status FROM reservations WHERE kind='user' AND name='famuser'")" = TOMBSTONED ]
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='keeper'")" = 1 ]
test -f "$repo/keeper-1-r1.apk"
if apk adbdump "$repo/Packages.adb" | grep -q 'name: fam-a'; then
	printf '%s\n' 'fam-a still indexed' >&2; exit 1
fi
apk adbdump "$repo/Packages.adb" | grep -q 'name: keeper'
apk verify --keys-dir "$keys" "$repo/Packages.adb" >/dev/null
printf '%s\n' 'family withdrawal with audit: OK'

# --- 4. re-withdrawal is a verified no-op ---
run_withdraw fam-a --reason 'retired upstream' --archive-dir "$test_root/archive" \
	> "$test_root/again.out" 2> "$test_root/again.err"
grep -E 'already withdrawn' "$test_root/again.out" >/dev/null
printf '%s\n' 'already-withdrawn no-op: OK'

# --- 5. unknown family and missing reason refuse ---
if run_withdraw nope --reason 'x' --archive-dir "$test_root/archive" >/dev/null 2>&1; then
	printf '%s\n' 'unknown family unexpectedly withdrew' >&2; exit 1
fi
if run_withdraw fam-a --archive-dir "$test_root/archive" >/dev/null 2>&1; then
	printf '%s\n' 'missing reason unexpectedly accepted' >&2; exit 1
fi
printf '%s\n' 'unknown/missing-arg refusal: OK'

# --- 6. stranded run refuses with restore pointer, then recovers ---
mkpkg fam-b 1-r1
stage_auth_txn "$incoming/famb-ready" fam-b fam-b fam-b-1-r1.apk
run_signer fam-b >/dev/null 2>&1
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1], timeout=30.0, isolation_level=None)
conn.execute("INSERT OR REPLACE INTO metadata(key, value) VALUES ('withdrawal_pending', 'fam-b')")
conn.commit()
PY
mkdir -p "$test_root/archive/fam-b"
mv "$repo/fam-b-1-r1.apk" "$test_root/archive/fam-b/fam-b-1-r1.apk"
if run_withdraw fam-b --reason 'x' --archive-dir "$test_root/archive" >/dev/null 2> "$test_root/str.err"; then
	printf '%s\n' 'stranded run unexpectedly proceeded' >&2; exit 1
fi
grep -E 'restore|heal' "$test_root/str.err" >/dev/null
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-b'")" = 1 ]
mv "$test_root/archive/fam-b/fam-b-1-r1.apk" "$repo/fam-b-1-r1.apk"
run_withdraw fam-b --reason 'x' --archive-dir "$test_root/archive" >/dev/null 2>&1
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-b'")" = 0 ]
printf '%s\n' 'stranded refusal and retry recovery: OK'

# --- 7. heal keeps the audit rows ---
run_signer --full-audit > "$test_root/heal.out" 2> "$test_root/heal.err"
[ "$(db_query 'SELECT COUNT(*) FROM withdrawals')" = 4 ]
grep -E 'heals repository' "$test_root/heal.out" >/dev/null
printf '%s\n' 'heal preserves audit: OK'

# --- 8. exact-NVR withdrawal touches only the named NVR ---------------
mkpkg fam-nvr 1.0-r1
mkpkg fam-nvr 1.0-r2
stage_auth_txn "$incoming/famnvr1-ready" fam-nvr fam-nvr fam-nvr-1.0-r1.apk
stage_auth_txn "$incoming/famnvr2-ready" fam-nvr fam-nvr fam-nvr-1.0-r2.apk
run_signer > "$test_root/nvrseed.out" 2> "$test_root/nvrseed.err"
test -f "$repo/fam-nvr-1.0-r1.apk"
test -f "$repo/fam-nvr-1.0-r2.apk"
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 2 ]
printf '%s\n' 'NVR family seed: OK (two revisions indexed)'

# --- 9. ambiguous version selection refuses before any mutation ------
before=$(find "$repo" -type f -printf '%s %p\n' | sort | sha256sum)
if run_withdraw fam-nvr=1.0 --reason 'retire old' --archive-dir "$test_root/archive" \
	> "$test_root/ambig.out" 2> "$test_root/ambig.err"; then
	printf '%s\n' 'ambiguous NVR selection unexpectedly withdrew' >&2
	exit 1
fi
grep -E 'ambiguous version selection' "$test_root/ambig.err" >/dev/null
grep -E 'fam-nvr-1.0-r1' "$test_root/ambig.err" >/dev/null
grep -E 'fam-nvr-1.0-r2' "$test_root/ambig.err" >/dev/null
[ "$before" = "$(find "$repo" -type f -printf '%s %p\n' | sort | sha256sum)" ]
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 2 ]
[ "$(db_query "SELECT COUNT(*) FROM withdrawals WHERE name='fam-nvr'")" = 0 ]
[ "$(db_query "SELECT COUNT(*) FROM metadata WHERE key='withdrawal_pending'")" = 0 ]
printf '%s\n' 'ambiguous selection refused pre-mutation, both candidates named: OK'

# --- 10. unknown NVR names what exists, mutates nothing ----------------
if run_withdraw fam-nvr=9.9-r9 --reason 'x' --archive-dir "$test_root/archive" \
	> "$test_root/unk.out" 2> "$test_root/unk.err"; then
	printf '%s\n' 'unknown NVR unexpectedly withdrew' >&2
	exit 1
fi
grep -E 'unknown NVR selection' "$test_root/unk.err" >/dev/null
grep -E 'fam-nvr-1.0-r1' "$test_root/unk.err" >/dev/null
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 2 ]
printf '%s\n' 'unknown NVR refused with inventory: OK'

# --- 11. exact withdrawal removes only the named NVR -------------------
run_withdraw fam-nvr=1.0-r2 --reason 'superseded' --archive-dir "$test_root/archive" \
	> "$test_root/nvrwd.out" 2> "$test_root/nvrwd.err"
test ! -e "$repo/fam-nvr-1.0-r2.apk"
test -f "$repo/fam-nvr-1.0-r1.apk"
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 1 ]
[ "$(db_query "SELECT nvr FROM packages WHERE name='fam-nvr'")" = 'fam-nvr-1.0-r1' ]
[ "$(db_query "SELECT COUNT(*) FROM withdrawals WHERE name='fam-nvr'")" = 1 ]
[ "$(db_query "SELECT nvr FROM withdrawals WHERE name='fam-nvr'")" = 'fam-nvr-1.0-r2' ]
[ "$(db_query "SELECT reason FROM withdrawals WHERE nvr='fam-nvr-1.0-r2'")" = 'superseded' ]
test -f "$test_root/archive/fam-nvr/fam-nvr-1.0-r2.apk"
test ! -e "$test_root/archive/fam-nvr/fam-nvr-1.0-r1.apk"
[ "$(db_query "SELECT COUNT(*) FROM files WHERE package_id NOT IN (SELECT package_id FROM packages) ")" = 0 ]
apk adbdump "$repo/Packages.adb" | grep -q 'name: fam-nvr'
if apk adbdump "$repo/Packages.adb" | grep -A2 'name: fam-nvr' | grep -q '1.0-r2'; then
	printf '%s\n' 'withdrawn NVR still indexed' >&2; exit 1
fi
apk verify --keys-dir "$keys" "$repo/Packages.adb" >/dev/null
printf '%s\n' 'exact-NVR withdrawal removes only the named NVR: OK'

# --- 12. re-withdraw of the same NVR is a verified no-op -------------
run_withdraw fam-nvr=1.0-r2 --reason 'superseded' --archive-dir "$test_root/archive" \
	> "$test_root/nvragain.out" 2> "$test_root/nvragain.err"
grep -E 'already withdrawn' "$test_root/nvragain.out" >/dev/null
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 1 ]
[ "$(db_query "SELECT COUNT(*) FROM withdrawals WHERE name='fam-nvr'")" = 1 ]
printf '%s\n' 'NVR re-withdrawal no-op: OK'

# --- 13. live dependents block even NVR-scoped withdrawal -------------
mkpkg dep-nvr 3-r1 '"fam-nvr"'
stage_auth_txn "$incoming/depnvr-ready" dep-nvr dep-nvr dep-nvr-3-r1.apk
run_signer dep-nvr >/dev/null 2>&1
before=$(find "$repo" -type f -printf '%s %p\n' | sort | sha256sum)
if run_withdraw fam-nvr=1.0-r1 --reason 'x' --archive-dir "$test_root/archive" \
	> "$test_root/nvrdep.out" 2> "$test_root/nvrdep.err"; then
	printf '%s\n' 'dependent-guarded NVR unexpectedly withdrew' >&2
	exit 1
fi
grep -E 'live dependents refuse' "$test_root/nvrdep.err" >/dev/null
[ "$before" = "$(find "$repo" -type f -printf '%s %p\n' | sort | sha256sum)" ]
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 1 ]
printf '%s\n' 'NVR withdrawal blocked by live dependent: OK'

# --- 14. withdrawing the last NVR tombstones owned identities ---------
run_withdraw dep-nvr --reason 'x' --archive-dir "$test_root/archive" >/dev/null 2>&1
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1], timeout=30.0, isolation_level=None)
conn.execute("INSERT INTO reservations(kind, name, numeric_id, owning_package, first_nvr, last_nvr, status, declaration_sha256) VALUES ('group', 'nvrgrp', 701, 'fam-nvr', 'fam-nvr-1.0-r1', 'fam-nvr-1.0-r1', 'ACTIVE', 'test')")
conn.commit()
PY
run_withdraw fam-nvr=1.0-r1 --reason 'retire line' --archive-dir "$test_root/archive" \
	> "$test_root/nvrlast.out" 2> "$test_root/nvrlast.err"
[ "$(db_query "SELECT COUNT(*) FROM packages WHERE name='fam-nvr'")" = 0 ]
[ "$(db_query "SELECT status FROM reservations WHERE kind='group' AND name='nvrgrp'")" = TOMBSTONED ]
grep -E 'tombstoned' "$test_root/nvrlast.out" >/dev/null
printf '%s\n' 'last-NVR withdrawal tombstones owned identities: OK'

printf '%s\n' 'withdraw-package: all cases OK'

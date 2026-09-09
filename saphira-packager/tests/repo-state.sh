#!/bin/sh

# SQLite repository metadata tests: migration, fast gates, eternal
# tombstones, full-audit healing, viewer goldens, lock contention, and
# the writer boundary (no JSON writes, no sidecars, no queue.db touch).
#
# usage: repo-state.sh SIGN-APK-REPO REPO-MIGRATE REPO-STATE MAKEPKG

set -eu

[ "$#" -eq 4 ] || {
	printf 'usage: %s SIGN-APK-REPO REPO-MIGRATE REPO-STATE MAKEPKG\n' "$0" >&2
	exit 1
}

sign_repo=$1
migrate_tool=$2
repo_state=$3
makepkg=$4
source_root=$(CDPATH= cd -- "$(dirname -- "$sign_repo")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-repo-state-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
repo=$test_root/repository/hatchling/x86_64
incoming=$test_root/incoming/x86_64
stage=$test_root/stage
artifacts=$test_root/artifacts
keys=$test_root/keys
mkdir -p "$repo" "$incoming" "$stage" "$artifacts" "$keys" "$test_root/package-tmp"

openssl genrsa -traditional -out "$test_root/test-repository.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$test_root/test-repository.rsa" -pubout -out "$keys/test-repository.rsa.pub" >/dev/null 2>&1

printf '%s\n' '# name	type	id	primary-group	home	shell	supplementary-groups' 'root	user	0	root	/root	/bin/bash	wheel' 'root	group	0	-	-	-	-' 'man	group	13	-	-	-	-' > "$test_root/accounts.tsv"

run_signer()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}

run_migrate()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$migrate_tool" "$@"
}

view()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_REPO_NAMES=hatchling \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub \
		"$repo_state" --gen hatchling "$@"
}

build_pkg()
{
	name=$1
	version=$2
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$name" >/dev/null
}

mk_txn()
{
	txn=$1
	target=$2
	apk=$3
	receipt_accounts=$4
	dir=$incoming/$txn-ready
	mkdir "$dir"
	cp "$artifacts/x86_64/$apk" "$dir/"
	printf '%s\n' "$target" > "$dir/target"
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$dir/package-seed.json"
	sha=$(sha256sum "$dir/$apk" | awk '{ print $1 }')
	name=${apk%-*-r*.apk}
	printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"'"$target"'","constructors":[{"constructor":"makepkg","producer":"'"$target"'","artifacts":[{"name":"'"$name"'","artifact":"'"$apk"'","sha256":"'"$sha"'","backend":"userns-maproot","accounts":'"$receipt_accounts"'}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$dir/artifact-manifest.json"
	(CDPATH= cd -- "$dir" && sha256sum "$apk" > manifest.sha256)
}

# Fixture packages: svcA v1 ships a fragment (uid/gid 660), plainB none.
mkdir -p "$stage/svcA/pkg/usr/bin" "$stage/svcA/pkg/usr/share/saphira/accounts.d" "$stage/plainB/pkg/usr/bin"
printf '%s\n' svcA > "$stage/svcA/pkg/usr/bin/svcA"
printf '%s\n' 'user svcuser 660 svcgroup /var/lib/svca /sbin/nologin' 'group svcgroup 660' 'dir /var/lib/svca 0755 svcuser svcgroup' > "$stage/svcA/pkg/usr/share/saphira/accounts.d/svcA"
printf '%s\n' plainB > "$stage/plainB/pkg/usr/bin/plainB"
printf '%s\n' '{"arch":"x86_64","build_time":1,"license":"MIT","name":"svcA","origin":"svcA","outputs":[{"dependencies":[],"description":"svcA","name":"svcA","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/svcA/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":1,"license":"MIT","name":"plainB","origin":"plainB","outputs":[{"dependencies":[],"description":"plainB","name":"plainB","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/plainB/manifest.json"
# Dependency stubs: makepkg attaches bare saphira-baselayout/bash/
# coreutils dependencies to fragment carriers, so declaration
# extraction (isolated tmp-root install) needs satisfiers in the repo.
# Plain stubs have no dependencies of their own: no recursion.
# bash-dev (NEWER than bash) is a deliberate prefix trap: provider
# resolution must match exact package names, never filename prefixes
# (gdbm-dev must never satisfy a gdbm dependency).
for stub in bash coreutils saphira-baselayout; do
	mkdir -p "$stage/$stub/pkg/usr/bin"
	printf '%s\n' "$stub" > "$stage/$stub/pkg/usr/bin/$stub"
	printf '%s\n' '{"arch":"x86_64","build_time":1,"license":"MIT","name":"'"$stub"'","origin":"'"$stub"'","outputs":[{"dependencies":[],"description":"'"$stub"'","name":"'"$stub"'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/$stub/manifest.json"
done
mkdir -p "$stage/bash-dev/pkg/usr/bin"
printf '%s\n' bash-dev > "$stage/bash-dev/pkg/usr/bin/bash-dev"
printf '%s\n' '{"arch":"x86_64","build_time":1,"license":"MIT","name":"bash-dev","origin":"bash-dev","outputs":[{"dependencies":[],"description":"bash-dev","name":"bash-dev","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"2-r0"}' > "$stage/bash-dev/manifest.json"
build_pkg svcA 1-r0
build_pkg plainB 1-r0
for stub in bash coreutils saphira-baselayout bash-dev; do
	build_pkg "$stub" 1-r0
done

# r48-era simulation: hand-place the APKs, sign an index, and write the
# ownership.json the JSON-era signer would have left behind.
cp "$artifacts/x86_64/svcA-1-r0.apk" "$artifacts/x86_64/plainB-1-r0.apk" \
	"$artifacts/x86_64/bash-1-r0.apk" "$artifacts/x86_64/coreutils-1-r0.apk" \
	"$artifacts/x86_64/saphira-baselayout-1-r0.apk" "$artifacts/x86_64/bash-dev-2-r0.apk" "$repo/"
# Published APKs are signed: the full audit verifies every repository
# signature before scanning, so the simulated archive must be too
# (adbsign takes one file per invocation; a multi-file call silently
# signs only the first).
for apk in "$repo"/*.apk; do
	apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$apk"
done
apk mkndx --allow-untrusted --hash sha256-160 -o "$repo/Packages.adb" "$repo"/*.apk
cp "$repo/Packages.adb" "$repo/APKINDEX.tar.gz"
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz"
apk verify --keys-dir "$keys" "$repo/Packages.adb"
python3 - "$source_root/saphira-packager/files/repo_db.py" "$repo" <<'PY'
import os
import sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import repo_db
import json
repo = sys.argv[2]
owners: dict = {}
idents = []
newest: dict = {}
for apk in sorted(os.listdir(repo)):
    if not apk.endswith(".apk"):
        continue
    info = repo_db.dump_package("apk", os.path.join(repo, apk))
    idents.append([info["name"], info["version"]])
    newest[info["name"]] = info["version"]
    for path in info["files"]:
        owners.setdefault(path, {})[info["name"]] = f"{info['name']}-{info['version']}"
with open(os.path.join(repo, "ownership.json"), "w", encoding="utf-8") as stream:
    json.dump({"schema": "saphira-ownership/v1",
               "identities": sorted(idents),
               "newest": {n: newest[n] for n in sorted(newest)},
               "owners": {p: owners[p] for p in sorted(owners)}},
              stream, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
PY
json_sha=$(sha256sum "$repo/ownership.json" | awk '{ print $1 }')

# A staged package waits while no database exists: bare signing refuses
# with a migration pointer (never a silent fallback), stages nothing,
# and creates no repository.db.
mkdir -p "$stage/plainC/pkg/usr/bin"
printf '%s\n' plainC > "$stage/plainC/pkg/usr/bin/plainC"
printf '%s\n' '{"arch":"x86_64","build_time":2,"license":"MIT","name":"plainC","origin":"plainC","outputs":[{"dependencies":[],"description":"plainC","name":"plainC","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/plainC/manifest.json"
build_pkg plainC 1-r0
mk_txn svcC plainC plainC-1-r0.apk '{"users":[],"groups":[],"dirs":[]}'
if run_signer > "$test_root/nodb.out" 2> "$test_root/nodb.err"; then
	printf '%s\n' 'signing without repository.db unexpectedly succeeded' >&2
	exit 1
fi
grep 'saphira-repo-migrate' "$test_root/nodb.err" >/dev/null
test ! -e "$repo/repository.db"
test -d "$incoming/svcC-ready"
test ! -e "$incoming/svcC-published"

# Explicit migration: census + carrier extraction + ledger + manifest,
# ownership.json frozen, accounts.json absence recorded (never made).
run_migrate hatchling > "$test_root/migrate.out" 2> "$test_root/migrate.err"
test -f "$repo/repository.db"
test -f "$repo/migration.json"
[ "$(stat -c %a "$repo/ownership.json")" = 444 ]
[ "$(sha256sum "$repo/ownership.json" | awk '{ print $1 }')" = "$json_sha" ]
test -z "$(find "$repo" -maxdepth 1 \( -name 'repository.db-wal' -o -name 'repository.db-shm' -o -name 'repository.db-journal' \) -print -quit)"
python3 - "$repo/migration.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)
assert manifest["schema"] == "saphira-repo-migration/v1"
assert manifest["tool"] == "migrate"
assert manifest["apk_identity_count"] == 6
assert manifest["carriers"] == ["svcA-1-r0.apk"], manifest["carriers"]
assert manifest["accounts_json_absent"] is True
assert manifest["active_reservations"] == 2, manifest
assert manifest["tombstoned_reservations"] == 0, manifest
assert manifest["history_complete"] is True
PY

# Viewer goldens on the migrated state (read-only; works unprivileged).
view summary | grep 'APK identities: *6' >/dev/null
view summary | grep 'active reservations: *2' >/dev/null
view packages | grep '^svcA-1-r0$' >/dev/null
view package svcA | grep 'svcA-1-r0' >/dev/null
view owner usr/bin/svcA | grep 'svcA-1-r0' >/dev/null
view users | grep 'user svcuser uid=660 package=svcA \[ACTIVE\]' >/dev/null
view user svcuser | grep 'uid=660 \[ACTIVE\]' >/dev/null
view gid 660 | grep 'group svcgroup' >/dev/null
view history svcA | grep 'svcA-1-r0' >/dev/null
view conflicts | grep 'no newest-view multi-owner paths' >/dev/null
view audit | grep '^OK:' >/dev/null
if view package nosuchpkg >/dev/null 2>&1; then
	printf '%s\n' 'viewer unexpectedly found a missing package' >&2
	exit 1
fi

# The staged package now publishes through the fast SQL path.
run_signer > "$test_root/svcC.out" 2> "$test_root/svcC.err"
test -f "$repo/plainC-1-r0.apk"
grep 'selective gate: repository state fresh' "$test_root/svcC.out" >/dev/null
grep 'staged gate:' "$test_root/svcC.out" >/dev/null
grep 'repository.db transaction committed' "$test_root/svcC.out" >/dev/null
test -d "$incoming/svcC-published"

# A UID collision with the ACTIVE reservation refuses loudly (the
# union sees the live declaration first).
mkdir -p "$stage/evilD/pkg/usr/bin" "$stage/evilD/pkg/usr/share/saphira/accounts.d"
printf '%s\n' evilD > "$stage/evilD/pkg/usr/bin/evilD"
printf '%s\n' 'user eviluser 660 evilgroup /var/lib/evilD /sbin/nologin' 'group evilgroup 661' > "$stage/evilD/pkg/usr/share/saphira/accounts.d/evilD"
printf '%s\n' '{"arch":"x86_64","build_time":3,"license":"MIT","name":"evilD","origin":"evilD","outputs":[{"dependencies":[],"description":"evilD","name":"evilD","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/evilD/manifest.json"
build_pkg evilD 1-r0
mk_txn evilD evilD evilD-1-r0.apk '{"users":[{"name":"eviluser","uid":"660","primary":"evilgroup","home":"/var/lib/evilD","shell":"/sbin/nologin"}],"groups":[{"name":"evilgroup","gid":"661"}],"dirs":[]}'
if run_signer evilD > "$test_root/evilD.out" 2> "$test_root/evilD.err"; then
	printf '%s\n' 'colliding Unix identity unexpectedly published' >&2
	exit 1
fi
grep 'account identity collision' "$test_root/evilD.err" >/dev/null
grep 'UID 660' "$test_root/evilD.err" >/dev/null
test ! -f "$repo/evilD-1-r0.apk"
rm -rf "$incoming/evilD-ready"

# svcA v2 drops the fragment: the binding tombstones, never frees.
# (Same stage dir, evolved recipe: version bump, fragment removed.)
rm -rf "$stage/svcA/pkg/usr/share/saphira/accounts.d" "$stage/svcA/artifact-manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":4,"license":"MIT","name":"svcA","origin":"svcA","outputs":[{"dependencies":[],"description":"svcA","name":"svcA","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"2-r0"}' > "$stage/svcA/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" svcA >/dev/null
mkdir "$incoming/svcAv2-ready"
cp "$artifacts/x86_64/svcA-2-r0.apk" "$incoming/svcAv2-ready/"
printf '%s\n' svcA > "$incoming/svcAv2-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/svcAv2-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"svcA","constructors":[{"constructor":"makepkg","producer":"svcA"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/svcAv2-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/svcAv2-ready" && sha256sum svcA-2-r0.apk > manifest.sha256)
run_signer svcA > "$test_root/svcAv2.out" 2> "$test_root/svcAv2.err"
test -f "$repo/svcA-2-r0.apk"
grep 'tombstoned' "$test_root/svcAv2.out" >/dev/null
view user svcuser | grep '\[TOMBSTONED\]' >/dev/null

# A full audit preserves tombstones (current-view reconcile verifies
# the ledger; it never destroys history it cannot see).
mkdir -p "$stage/plainE/pkg/usr/bin"
printf '%s\n' plainE > "$stage/plainE/pkg/usr/bin/plainE"
printf '%s\n' '{"arch":"x86_64","build_time":5,"license":"MIT","name":"plainE","origin":"plainE","outputs":[{"dependencies":[],"description":"plainE","name":"plainE","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/plainE/manifest.json"
build_pkg plainE 1-r0
mk_txn plainE plainE plainE-1-r0.apk '{"users":[],"groups":[],"dirs":[]}'
run_signer --full-audit plainE > "$test_root/audit.out" 2> "$test_root/audit.err"
test -f "$repo/plainE-1-r0.apk"
grep 'full audit:' "$test_root/audit.out" >/dev/null
view user svcuser | grep '\[TOMBSTONED\]' >/dev/null
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
assert conn.execute("SELECT COUNT(*) FROM reservations WHERE status='TOMBSTONED'").fetchone()[0] == 2
PY

# The tombstoned UID still refuses strangers (now via the eternal
# ledger, since the union no longer sees the dropped declaration),
# but the same lineage may reclaim its canonical ID.
mk_txn evilD2 evilD evilD-1-r0.apk '{"users":[{"name":"eviluser","uid":"660","primary":"evilgroup","home":"/var/lib/evilD","shell":"/sbin/nologin"}],"groups":[{"name":"evilgroup","gid":"661"}],"dirs":[]}'
if run_signer evilD > "$test_root/evilD2.out" 2> "$test_root/evilD2.err"; then
	printf '%s\n' 'tombstoned UID reuse unexpectedly published' >&2
	exit 1
fi
grep 'TOMBSTONED reservation' "$test_root/evilD2.err" >/dev/null
rm -rf "$incoming/evilD2-ready"
# svcA v3 restores the fragment: the same lineage reclaims its
# canonical ID and the binding reactivates.
mkdir -p "$stage/svcA/pkg/usr/share/saphira/accounts.d"
rm -f "$stage/svcA/artifact-manifest.json"
printf '%s\n' 'user svcuser 660 svcgroup /var/lib/svca /sbin/nologin' 'group svcgroup 660' > "$stage/svcA/pkg/usr/share/saphira/accounts.d/svcA"
printf '%s\n' '{"arch":"x86_64","build_time":6,"license":"MIT","name":"svcA","origin":"svcA","outputs":[{"dependencies":[],"description":"svcA","name":"svcA","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"3-r0"}' > "$stage/svcA/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" svcA >/dev/null
mkdir "$incoming/svcAv3-ready"
cp "$artifacts/x86_64/svcA-3-r0.apk" "$incoming/svcAv3-ready/"
printf '%s\n' svcA > "$incoming/svcAv3-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/svcAv3-ready/package-seed.json"
v3sha=$(sha256sum "$incoming/svcAv3-ready/svcA-3-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"svcA","constructors":[{"constructor":"makepkg","producer":"svcA","artifacts":[{"name":"svcA","artifact":"svcA-3-r0.apk","sha256":"'"$v3sha"'","backend":"userns-maproot","accounts":{"users":[{"name":"svcuser","uid":"660","primary":"svcgroup","home":"/var/lib/svca","shell":"/sbin/nologin"}],"groups":[{"name":"svcgroup","gid":"660"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/svcAv3-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/svcAv3-ready" && sha256sum svcA-3-r0.apk > manifest.sha256)
run_signer svcA > "$test_root/svcAv3.out" 2> "$test_root/svcAv3.err"
test -f "$repo/svcA-3-r0.apk"
view user svcuser | grep '\[ACTIVE\]' >/dev/null
view user svcuser | grep 'last seen: *svcA-3-r0' >/dev/null

# Writer lock contention dies loudly with nothing mutated.
mkdir "$repo/repository.db.lock"
mkdir -p "$stage/plainF/pkg/usr/bin"
printf '%s\n' plainF > "$stage/plainF/pkg/usr/bin/plainF"
printf '%s\n' '{"arch":"x86_64","build_time":7,"license":"MIT","name":"plainF","origin":"plainF","outputs":[{"dependencies":[],"description":"plainF","name":"plainF","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/plainF/manifest.json"
build_pkg plainF 1-r0
mk_txn plainF plainF plainF-1-r0.apk '{"users":[],"groups":[],"dirs":[]}'
if run_signer plainF > "$test_root/lock.out" 2> "$test_root/lock.err"; then
	printf '%s\n' 'publication under a held lock unexpectedly succeeded' >&2
	exit 1
fi
grep 'writer lock already held' "$test_root/lock.err" >/dev/null
test ! -f "$repo/plainF-1-r0.apk"
rmdir "$repo/repository.db.lock"
rm -rf "$incoming/plainF-ready"

# Writer boundary, end to end: the frozen JSON was never rewritten, no
# accounts.json was ever manufactured, no sidecars exist, and none of
# these tools can even name the controller database.
[ "$(sha256sum "$repo/ownership.json" | awk '{ print $1 }')" = "$json_sha" ]
test ! -e "$repo/accounts.json"
test -z "$(find "$repo" -maxdepth 1 \( -name 'repository.db-wal' -o -name 'repository.db-shm' -o -name 'repository.db-journal' \) -print -quit)"
test -z "$(find "$test_root" -maxdepth 1 -name '.*' -print -quit)"
if grep -r "queue\.db" "$source_root/saphira-packager/files/sign-apk-repo" "$source_root/saphira-packager/files/saphira-repo-migrate" "$source_root/saphira-packager/files/saphira-repo-state" "$source_root/saphira-packager/files/promote-repo" "$source_root/saphira-packager/files/seed-repo" "$source_root/saphira-packager/files/repo_db.py" 2>/dev/null; then
	printf '%s\n' 'repository tooling references queue.db' >&2
	exit 1
fi

printf '%s\n' 'repository.db migration, fast SQL gates, eternal tombstones, full-audit healing, viewer goldens, lock contention, and writer-boundary tests: OK'

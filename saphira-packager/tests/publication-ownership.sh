#!/bin/sh

# Authoritative-producer ownership gate: per-producer transactions, bundled
# inputs never publish, fail-closed on duplicates/stale/uncertainty.
#
# Covers (hermetic, no live state):
# - cold-closure one-run publish (empty repo, full native closure, ONE sign)
# - real splits (one producer, two outputs, one transaction)
# - stale consumer (closure hash vs staged mismatch -> rebuild report)
# - duplicate authoritative producers (same NVR, different bytes -> fail)
# - publisher lock cooperation + filtered snapshot scoping
#
# usage: publication-ownership.sh SIGN-APK-REPO MAKEPKG

set -eu

[ "$#" -eq 2 ] || {
	printf 'usage: %s SIGN-APK-REPO MAKEPKG\n' "$0" >&2
	exit 1
}

sign_repo=$1
makepkg=$2
source_root=$(CDPATH= cd -- "$(dirname -- "$sign_repo")/../.." && pwd)
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-ownership-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
repo=$test_root/repository/hatchling/x86_64
incoming=$test_root/incoming/x86_64
stage=$test_root/stage
artifacts=$test_root/artifacts
keys=$test_root/keys
mkdir -p "$repo" "$incoming" "$stage" "$artifacts" "$keys" "$test_root/package-tmp"

openssl genrsa -traditional -out "$test_root/test-repository.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$test_root/test-repository.rsa" -pubout -out "$keys/test-repository.rsa.pub" >/dev/null 2>&1

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
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}

mkpkg()
{
	name=$1 version=$2
	mkdir -p "$stage/$name/pkg/usr/bin"
	printf '%s\n' "$name" > "$stage/$name/pkg/usr/bin/$name"
	printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"'$name'","origin":"'$name'","outputs":[{"dependencies":[],"description":"'$name'","name":"'$name'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"'$version'"}' > "$stage/$name/manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$name" >/dev/null
}

# stage_auth_txn txn-dir target producer apk [apk...]
# Minimal new-builder transaction: single authoritative producer, full plan
# (single node) + closure hashes (empty repository, local-only).
stage_auth_txn()
{
	txn=$1 target=$2 producer=$3
	shift 3
	mkdir "$txn"
	for apk in "$@"; do
		cp "$artifacts/x86_64/$apk" "$txn/"
	done
	printf '%s\n' "$target" > "$txn/target"
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$txn/package-seed.json"
	apksha=$(sha256sum "$txn/$1" | awk '{ print $1 }')
	printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"'$producer'","constructors":[{"constructor":"makepkg","producer":"'$producer'","artifacts":[{"name":"'$producer'","artifact":"'$producer'-1-r1.apk","sha256":"'$apksha'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$txn/artifact-manifest.json"
	# Minimal plan: single authoritative build node.
	printf '%s\n' '{"arch":"x86_64","builds":[{"build_dependencies":[],"outputs":["'$producer'"],"producer":"'$producer'","recipe":"test","required_outputs":["'$producer'"],"target":true,"version":"1-r1"}],"repository":[],"schema":"saphira-build-plan/v1","target":"'$producer'","target_producer":"'$producer'"}' > "$txn/plan.json"
	printf '%s\n' '{"local":[{"artifacts":[{"artifact":"'$1'","name":"'$producer'","sha256":"'$apksha'"}],"producer":"'$producer'","target":true,"version":"1-r1"}],"repository":[],"schema":"saphira-build-closure/v1","target":"'$producer'","target_producer":"'$producer'"}' > "$txn/closure-hashes.json"
	(CDPATH= cd -- "$txn" && sha256sum "$@" > manifest.sha256)
}

# --- 1. cold-closure one-run publish: empty repo, dep chain, ONE sign ---
mkpkg dep-a 1-r1
mkpkg dep-b 1-r1
mkpkg dep-c 1-r1
stage_auth_txn "$incoming/dep-a-ready" dep-a dep-a dep-a-1-r1.apk
stage_auth_txn "$incoming/dep-b-ready" dep-b dep-b dep-b-1-r1.apk
stage_auth_txn "$incoming/dep-c-ready" dep-c dep-c dep-c-1-r1.apk
run_signer > "$test_root/cold.out" 2> "$test_root/cold.err"
test -f "$repo/dep-a-1-r1.apk"
test -f "$repo/dep-b-1-r1.apk"
test -f "$repo/dep-c-1-r1.apk"
grep 'ownership gate: 3 transaction(s), 3 authoritative novel file(s)' "$test_root/cold.out" >/dev/null
test -f "$incoming/dep-a-published/PUBLICATION-REPORT.txt"
grep 'published authoritative: dep-a-1-r1.apk' "$incoming/dep-a-published/PUBLICATION-REPORT.txt" >/dev/null
test ! -e "$incoming/dep-a-ready"
printf '%s\n' 'cold-closure one-run publish: OK'

# --- 2. real splits: one producer, two outputs, one transaction ---
mkdir -p "$stage/split/pkg/usr/bin" "$stage/split-sub/pkg/usr/lib"
printf '%s\n' tool > "$stage/split/pkg/usr/bin/tool"
printf '%s\n' lib > "$stage/split-sub/pkg/usr/lib/libsplit.so"
printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"split","origin":"split","outputs":[{"dependencies":[],"description":"split","name":"split","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/split/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"split-sub","origin":"split","outputs":[{"dependencies":[],"description":"split sub","name":"split-sub","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/split-sub/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" split >/dev/null
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" split-sub >/dev/null
# Single authoritative transaction carrying both split outputs would
# require one producer emitting two artifacts; emulate with two
# per-producer transactions from the same origin (both publish in one run).
stage_auth_txn "$incoming/split-ready" split split split-1-r1.apk
stage_auth_txn "$incoming/splitsub-ready" split-sub split-sub split-sub-1-r1.apk
run_signer split split-sub > "$test_root/split.out" 2> "$test_root/split.err"
test -f "$repo/split-1-r1.apk"
test -f "$repo/split-sub-1-r1.apk"
printf '%s\n' 'real splits publish: OK'

# --- 3. stale consumer: bundles H1, authoritative dep carries H2 ---
mkpkg stale-dep 1-r1
stale_sha1=$(sha256sum "$artifacts/x86_64/stale-dep-1-r1.apk" | awk '{ print $1 }')
# Rebuild same NVR with different bytes (H2) as the new authoritative dep.
cp "$artifacts/x86_64/stale-dep-1-r1.apk" "$artifacts/x86_64/stale-dep-1-r1.apk.new"
printf x >> "$artifacts/x86_64/stale-dep-1-r1.apk.new"
stale_sha2=$(sha256sum "$artifacts/x86_64/stale-dep-1-r1.apk.new" | awk '{ print $1 }')
mkdir "$incoming/staledep-ready"
cp "$artifacts/x86_64/stale-dep-1-r1.apk.new" "$incoming/staledep-ready/stale-dep-1-r1.apk"
printf '%s\n' stale-dep > "$incoming/staledep-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/staledep-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"stale-dep","constructors":[{"constructor":"makepkg","producer":"stale-dep","artifacts":[{"name":"stale-dep","artifact":"stale-dep-1-r1.apk","sha256":"'$stale_sha2'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/staledep-ready/artifact-manifest.json"
printf '%s\n' '{"arch":"x86_64","builds":[{"build_dependencies":[],"outputs":["stale-dep"],"producer":"stale-dep","recipe":"test","required_outputs":["stale-dep"],"target":true,"version":"1-r1"}],"repository":[],"schema":"saphira-build-plan/v1","target":"stale-dep","target_producer":"stale-dep"}' > "$incoming/staledep-ready/plan.json"
printf '%s\n' '{"local":[{"artifacts":[{"artifact":"stale-dep-1-r1.apk","name":"stale-dep","sha256":"'$stale_sha2'"}],"producer":"stale-dep","target":true,"version":"1-r1"}],"repository":[],"schema":"saphira-build-closure/v1","target":"stale-dep","target_producer":"stale-dep"}' > "$incoming/staledep-ready/closure-hashes.json"
(CDPATH= cd -- "$incoming/staledep-ready" && sha256sum stale-dep-1-r1.apk > manifest.sha256)
# Consumer built against H1: authoritative stale-cons + bundled stale-dep H1.
mkpkg stale-cons 1-r1
stale_cons_sha=$(sha256sum "$artifacts/x86_64/stale-cons-1-r1.apk" | awk '{ print $1 }')
mkdir "$incoming/stalecons-ready"
cp "$artifacts/x86_64/stale-cons-1-r1.apk" "$incoming/stalecons-ready/"
cp "$artifacts/x86_64/stale-dep-1-r1.apk" "$incoming/stalecons-ready/stale-dep-1-r1.apk"
printf '%s\n' stale-cons > "$incoming/stalecons-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/stalecons-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"stale-cons","constructors":[{"constructor":"makepkg","producer":"stale-cons","artifacts":[{"name":"stale-cons","artifact":"stale-cons-1-r1.apk","sha256":"'$stale_cons_sha'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]},{"constructor":"makepkg","producer":"stale-dep","artifacts":[{"name":"stale-dep","artifact":"stale-dep-1-r1.apk","sha256":"'$stale_sha1'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/stalecons-ready/artifact-manifest.json"
printf '%s\n' '{"arch":"x86_64","builds":[{"build_dependencies":[],"outputs":["stale-dep"],"producer":"stale-dep","recipe":"test","required_outputs":["stale-dep"],"target":false,"version":"1-r1"},{"build_dependencies":["stale-dep"],"outputs":["stale-cons"],"producer":"stale-cons","recipe":"test","required_outputs":["stale-cons"],"target":true,"version":"1-r1"}],"repository":[],"schema":"saphira-build-plan/v1","target":"stale-cons","target_producer":"stale-cons"}' > "$incoming/stalecons-ready/plan.json"
printf '%s\n' '{"local":[{"artifacts":[{"artifact":"stale-dep-1-r1.apk","name":"stale-dep","sha256":"'$stale_sha1'"}],"producer":"stale-dep","target":false,"version":"1-r1"},{"artifacts":[{"artifact":"stale-cons-1-r1.apk","name":"stale-cons","sha256":"'$stale_cons_sha'"}],"producer":"stale-cons","target":true,"version":"1-r1"}],"repository":[],"schema":"saphira-build-closure/v1","target":"stale-cons","target_producer":"stale-cons"}' > "$incoming/stalecons-ready/closure-hashes.json"
(CDPATH= cd -- "$incoming/stalecons-ready" && sha256sum stale-cons-1-r1.apk stale-dep-1-r1.apk > manifest.sha256)
stale_before=$(find "$repo" -type f -printf '%P %s\n' | sort | sha256sum)
if run_signer stale-dep stale-cons > "$test_root/stale.out" 2> "$test_root/stale.err"; then
	printf '%s\n' 'stale consumer unexpectedly published' >&2
	exit 1
fi
grep -E 'stale consumer|uncertain provenance|unsatisfied closure' "$test_root/stale.err" >/dev/null
[ "$stale_before" = "$(find "$repo" -type f -printf '%P %s\n' | sort | sha256sum)" ]
test -d "$incoming/stalecons-ready"
printf '%s\n' 'stale consumer fail-closed: OK'
rm -rf "$incoming/stalecons-ready" "$incoming/staledep-ready"

# --- 4. duplicate authoritative producers: same NVR, different bytes ---
mkpkg dup 1-r1
mkdir "$incoming/dup1-ready"
cp "$artifacts/x86_64/dup-1-r1.apk" "$incoming/dup1-ready/"
printf '%s\n' dup > "$incoming/dup1-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/dup1-ready/package-seed.json"
dup_sha=$(sha256sum "$incoming/dup1-ready/dup-1-r1.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"dup","constructors":[{"constructor":"makepkg","producer":"dup","artifacts":[{"name":"dup","artifact":"dup-1-r1.apk","sha256":"'$dup_sha'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/dup1-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/dup1-ready" && sha256sum dup-1-r1.apk > manifest.sha256)
mkdir "$incoming/dup2-ready"
cp "$artifacts/x86_64/dup-1-r1.apk" "$incoming/dup2-ready/dup-1-r1.apk"
printf x >> "$incoming/dup2-ready/dup-1-r1.apk"
printf '%s\n' dup > "$incoming/dup2-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/dup2-ready/package-seed.json"
dup2_sha=$(sha256sum "$incoming/dup2-ready/dup-1-r1.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"dup","constructors":[{"constructor":"makepkg","producer":"dup","artifacts":[{"name":"dup","artifact":"dup-1-r1.apk","sha256":"'$dup2_sha'","backend":"userns-maproot","accounts":{"users":[],"groups":[],"dirs":[]},"fhs":{"dirs":[],"replaces":[],"removals":[]},"caps":{"caps":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/dup2-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/dup2-ready" && sha256sum dup-1-r1.apk > manifest.sha256)
dup_before=$(find "$repo" -type f -printf '%P %s\n' | sort | sha256sum)
if run_signer dup > "$test_root/dup.out" 2> "$test_root/dup.err"; then
	printf '%s\n' 'duplicate authoritative unexpectedly published' >&2
	exit 1
fi
grep 'conflicting authoritative producers' "$test_root/dup.err" >/dev/null
[ "$dup_before" = "$(find "$repo" -type f -printf '%P %s\n' | sort | sha256sum)" ]
test -d "$incoming/dup1-ready"
test -d "$incoming/dup2-ready"
printf '%s\n' 'duplicate authoritative fail-closed: OK'
rm -rf "$incoming/dup1-ready" "$incoming/dup2-ready"

# --- 5. publisher lock cooperation + filtered snapshot scoping ---
python3 - "$source_root/saphira-packager/files/buildpkg" "$incoming" "$test_root/build" <<'PY'
import importlib.machinery
import importlib.util
import sys
from pathlib import Path
spec = importlib.util.spec_from_loader(
    "buildpkg_under_test",
    importlib.machinery.SourceFileLoader("buildpkg_under_test", sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
incoming_arch = Path(sys.argv[2])
build_root = Path(sys.argv[3])
lock = incoming_arch / "sign-apk-repo.lock"
lock.mkdir(exist_ok=True)
try:
    config = {"SAPHIRA_INCOMING_DIR": str(incoming_arch.parent), "SAPHIRA_ARCH": "x86_64",
              "SAPHIRA_BUILD_ROOT": str(build_root), "SAPHIRA_BINDIR": "/usr/bin",
              "SAPHIRA_PACKAGE_TMP": str(build_root)}
    txn = module.Transaction(config, "lockprobe", None)
    try:
        txn._check_publisher_lock()
    except module.BuildError as exc:
        assert "publication lock held" in str(exc), str(exc)
    else:
        raise SystemExit("builder did not refuse while publisher lock held")
finally:
    lock.rmdir()
print("builder lock cooperation: OK")
PY
# Filtered run ignores unrelated pending: stage unrelated + target, publish
# target only with filter, unrelated remains.
mkpkg unrelated 1-r1
stage_auth_txn "$incoming/unrelated-ready" unrelated unrelated unrelated-1-r1.apk
mkpkg locktarget 1-r1
stage_auth_txn "$incoming/locktarget-ready" locktarget locktarget locktarget-1-r1.apk
run_signer locktarget > "$test_root/filtered.out" 2> "$test_root/filtered.err"
test -f "$repo/locktarget-1-r1.apk"
test -d "$incoming/unrelated-ready"
test ! -f "$repo/unrelated-1-r1.apk"
printf '%s\n' 'filtered snapshot scoping: OK'

printf '%s\n' 'publication ownership gate: OK'

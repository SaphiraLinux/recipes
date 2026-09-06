#!/bin/sh

set -eu

[ "$#" -eq 3 ] || {
	printf 'usage: %s SIGN-APK-REPO MAKEPKG CHECKPKG\n' "$0" >&2
	exit 1
}

sign_repo=$1
makepkg=$2
checkpkg=$3
source_root=$(CDPATH= cd -- "$(dirname -- "$sign_repo")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-publication-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
repo=$test_root/repository/hatchling/x86_64
incoming=$test_root/incoming/x86_64
stage=$test_root/stage
artifacts=$test_root/artifacts
keys=$test_root/keys
mkdir -p "$repo" "$incoming" "$stage/make/pkg/usr/bin" "$artifacts" "$keys" "$test_root/package-tmp"

openssl genrsa -traditional -out "$test_root/test-repository.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$test_root/test-repository.rsa" -pubout -out "$keys/test-repository.rsa.pub" >/dev/null 2>&1

printf '%s\n' make > "$stage/make/pkg/usr/bin/make"
printf '%s\n' '{"arch":"x86_64","build_time":1,"license":"GPL-3.0-or-later","name":"make","origin":"make","outputs":[{"dependencies":[],"description":"GNU make","name":"make","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/make/","version":"9-r0"}' > "$stage/make/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" make >/dev/null

ready=$incoming/make-fixture-ready
mkdir "$ready"
cp "$artifacts/x86_64/make-9-r0.apk" "$ready/"
printf '%s\n' make > "$ready/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$ready/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"make","constructors":[{"constructor":"makepkg","producer":"make"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$ready/artifact-manifest.json"
(CDPATH= cd -- "$ready" && sha256sum make-9-r0.apk > manifest.sha256)

run_signer()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}

run_signer >/dev/null
test -f "$repo/make-9-r0.apk"
test -f "$repo/Packages.adb"
test -f "$repo/APKINDEX.tar.gz"
apk verify --keys-dir "$keys" "$repo/make-9-r0.apk"
apk verify --keys-dir "$keys" "$repo/Packages.adb"
apk verify --keys-dir "$keys" "$repo/APKINDEX.tar.gz"
test -d "$incoming/make-fixture-published"
test ! -e "$ready"
[ "$(apk adbdump "$repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 1 ]
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub \
SAPHIRA_REPO_NAMES=hatchling \
	"$checkpkg" make >/dev/null

# A pure-rebuild transaction (every package a same-NVR rebuild with
# different bytes) is retired AUTOMATICALLY: nothing in it could ever
# publish, the published copy wins, and the transaction is retained as
# evidence under .superseded-conflict. Repository and index stay untouched.
conflict=$incoming/conflict-fixture-ready
mkdir "$conflict"
cp "$incoming/make-fixture-published"/{target,artifact-manifest.json,bootstrap-seed.json} "$conflict/"
cp "$repo/make-9-r0.apk" "$conflict/make-9-r0.apk"
printf x >> "$conflict/make-9-r0.apk"
(CDPATH= cd -- "$conflict" && sha256sum make-9-r0.apk > manifest.sha256)
before=$(sha256sum "$repo/make-9-r0.apk" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz")
run_signer > "$test_root/conflict.out" 2> "$test_root/conflict.err"
grep 'auto-retired pure-rebuild transaction conflict-fixture-ready' "$test_root/conflict.out" >/dev/null
grep 'nothing left to publish after automatic retirement' "$test_root/conflict.out" >/dev/null
after=$(sha256sum "$repo/make-9-r0.apk" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz")
[ "$before" = "$after" ]
test -d "$conflict.superseded-conflict"
test -f "$conflict.superseded-conflict/RETIRED-NOTE.txt"
grep 'Published NVRs are immutable' "$conflict.superseded-conflict/RETIRED-NOTE.txt" >/dev/null
test -z "$(find "$test_root" -mindepth 1 -name '.*' -print -quit)"

# A MIXED transaction (publishable novel package + conflicting rebuild) is
# NOT auto-retired: publication stops loudly and nothing is mutated, so the
# novel outputs are not discarded alongside the rebuild.
mixed=$incoming/mixed-fixture-ready
mkdir "$mixed"
mkdir -p "$stage/m4/pkg/usr/bin"
printf '%s\n' m4 > "$stage/m4/pkg/usr/bin/m4"
printf '%s\n' '{"arch":"x86_64","build_time":2,"license":"GPL-3.0-or-later","name":"m4","origin":"m4","outputs":[{"dependencies":[],"description":"GNU m4","name":"m4","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/m4/","version":"1-r0"}' > "$stage/m4/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" m4 >/dev/null
cp "$incoming/make-fixture-published"/{target,artifact-manifest.json,bootstrap-seed.json} "$mixed/"
cp "$repo/make-9-r0.apk" "$mixed/make-9-r0.apk"
printf x >> "$mixed/make-9-r0.apk"
cp "$artifacts/x86_64/m4-1-r0.apk" "$mixed/m4-1-r0.apk"
(CDPATH= cd -- "$mixed" && sha256sum make-9-r0.apk m4-1-r0.apk > manifest.sha256)
mixed_before=$(sha256sum "$repo/make-9-r0.apk" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz")
if run_signer > "$test_root/mixed.out" 2> "$test_root/mixed.err"; then
	printf '%s\n' 'mixed transaction unexpectedly published' >&2
	exit 1
fi
grep 'automatic retirement is not safe' "$test_root/mixed.err" >/dev/null
grep 'filename is immutable' "$test_root/mixed.err" >/dev/null
[ "$mixed_before" = "$(sha256sum "$repo/make-9-r0.apk" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz")" ]
test -d "$mixed"
test ! -e "$mixed.superseded-conflict"

# A listed generation repository that does not exist refuses publication
# before any repository or index mutation.
mkdir "$incoming/ghost-fixture-ready"
cp "$artifacts/x86_64/make-9-r0.apk" "$incoming/ghost-fixture-ready/make-9-r0.apk"
printf '%s\n' make > "$incoming/ghost-fixture-ready/target"
cp "$incoming/make-fixture-published/bootstrap-seed.json" "$incoming/ghost-fixture-ready/"
cp "$incoming/make-fixture-published/artifact-manifest.json" "$incoming/ghost-fixture-ready/"
(CDPATH= cd -- "$incoming/ghost-fixture-ready" && sha256sum make-9-r0.apk > manifest.sha256)
ghost_before=$(find "$repo" -type f -printf '%f %s\n' | sort | sha256sum)
if SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling ghost' \
	unshare --map-root-user "$sign_repo" > "$test_root/ghost.out" 2> "$test_root/ghost.err"; then
	printf '%s\n' 'publication into a missing generation repository unexpectedly succeeded' >&2
	exit 1
fi
grep 'generation repository does not exist' "$test_root/ghost.err" >/dev/null
[ "$ghost_before" = "$(find "$repo" -type f -printf '%f %s\n' | sort | sha256sum)" ]
rm -rf "$incoming/ghost-fixture-ready"

# Multi-repository publication: one ready transaction lands in every
# listed generation repository, each keeping its own signed index.
rm -rf "$conflict.superseded-conflict" "$mixed"
mkdir -p "$test_root/repository/hatched/x86_64"
mkdir -p "$stage/gawk/pkg/usr/bin"
printf '%s\n' gawk > "$stage/gawk/pkg/usr/bin/gawk"
printf '%s\n' '{"arch":"x86_64","build_time":2,"license":"GPL-3.0-or-later","name":"gawk","origin":"gawk","outputs":[{"dependencies":[],"description":"GNU awk","name":"gawk","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/gawk/","version":"1-r0"}' > "$stage/gawk/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" gawk >/dev/null
dual=$incoming/gawk-fixture-ready
mkdir "$dual"
cp "$artifacts/x86_64/gawk-1-r0.apk" "$dual/"
printf '%s\n' gawk > "$dual/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$dual/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"gawk","constructors":[{"constructor":"makepkg","producer":"gawk"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$dual/artifact-manifest.json"
(CDPATH= cd -- "$dual" && sha256sum gawk-1-r0.apk > manifest.sha256)
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling hatched' \
	unshare --map-root-user "$sign_repo" >/dev/null
hatched_repo=$test_root/repository/hatched/x86_64
test -f "$hatched_repo/gawk-1-r0.apk"
test -f "$repo/gawk-1-r0.apk"
for index in "$repo/Packages.adb" "$repo/APKINDEX.tar.gz" \
	"$hatched_repo/Packages.adb" "$hatched_repo/APKINDEX.tar.gz"; do
	apk verify --keys-dir "$keys" "$index"
done
[ "$(apk adbdump "$repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 2 ]
[ "$(apk adbdump "$hatched_repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 1 ]
test -d "$incoming/gawk-fixture-published"

# Divergent generations: a filename already published in one repository
# is installed only into the repositories missing it - no duplicate set
# entries, no concurrency-guard trip, both indexes stay valid.
mkdir -p "$stage/mawk/pkg/usr/bin"
printf '%s\n' mawk > "$stage/mawk/pkg/usr/bin/mawk"
printf '%s\n' '{"arch":"x86_64","build_time":3,"license":"GPL-3.0-or-later","name":"mawk","origin":"mawk","outputs":[{"dependencies":[],"description":"minimal awk","name":"mawk","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/mawk/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" mawk >/dev/null
cp "$artifacts/x86_64/mawk-1-r0.apk" "$repo/"
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$repo/mawk-1-r0.apk"
div=$incoming/mawk-fixture-ready
mkdir "$div"
cp "$artifacts/x86_64/mawk-1-r0.apk" "$div/"
printf '%s\n' mawk > "$div/target"
cp "$incoming/gawk-fixture-published/bootstrap-seed.json" "$div/"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"mawk","constructors":[{"constructor":"makepkg","producer":"mawk"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$div/artifact-manifest.json"
(CDPATH= cd -- "$div" && sha256sum mawk-1-r0.apk > manifest.sha256)
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling hatched' \
	unshare --map-root-user "$sign_repo" >/dev/null
test -f "$hatched_repo/mawk-1-r0.apk"
test -f "$repo/mawk-1-r0.apk"
[ "$(apk adbdump "$repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 3 ]
[ "$(apk adbdump "$hatched_repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 2 ]
test -d "$incoming/mawk-fixture-published"

# File-ownership collision gate: two packages claiming the same path in one
# transaction refuse publication without mutating anything. The classic
# case: tar and cpio both shipping upstream paxutils' rmt.
mkdir -p "$stage/tar/pkg/usr/libexec" "$stage/tar/pkg/usr/bin" "$stage/cpio/pkg/usr/libexec" "$stage/cpio/pkg/usr/bin"
printf '%s\n' rmt > "$stage/tar/pkg/usr/libexec/rmt"
printf '%s\n' tar > "$stage/tar/pkg/usr/bin/tar"
printf '%s\n' rmt > "$stage/cpio/pkg/usr/libexec/rmt"
printf '%s\n' cpio > "$stage/cpio/pkg/usr/bin/cpio"
printf '%s\n' '{"arch":"x86_64","build_time":3,"license":"GPL-3.0-or-later","name":"tar","origin":"tar","outputs":[{"dependencies":[],"description":"tar","name":"tar","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/tar/","version":"1-r0"}' > "$stage/tar/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":3,"license":"GPL-3.0-or-later","name":"cpio","origin":"cpio","outputs":[{"dependencies":[],"description":"cpio","name":"cpio","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/cpio/","version":"1-r0"}' > "$stage/cpio/manifest.json"
for fixture in tar cpio; do
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$fixture" >/dev/null
done
ownfix=$incoming/ownfix-ready
mkdir "$ownfix"
cp "$artifacts/x86_64/tar-1-r0.apk" "$artifacts/x86_64/cpio-1-r0.apk" "$ownfix/"
printf '%s\n' cpio > "$ownfix/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$ownfix/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"cpio","constructors":[{"constructor":"makepkg","producer":"cpio"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$ownfix/artifact-manifest.json"
(CDPATH= cd -- "$ownfix" && sha256sum tar-1-r0.apk cpio-1-r0.apk > manifest.sha256)
ownfix_before=$(sha256sum "$repo/make-9-r0.apk" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz")
if run_signer > "$test_root/ownfix.out" 2> "$test_root/ownfix.err"; then
	printf '%s\n' 'ownership collision unexpectedly published' >&2
	exit 1
fi
grep 'file ownership collision' "$test_root/ownfix.err" >/dev/null
grep 'usr/libexec/rmt' "$test_root/ownfix.err" >/dev/null
[ "$ownfix_before" = "$(sha256sum "$repo/make-9-r0.apk" "$repo/Packages.adb" "$repo/APKINDEX.tar.gz")" ]
test -d "$ownfix"

# After the split is corrected at source (tar stops shipping rmt; cpio owns
# it), the corrected payload ships as a NEW version (published artifacts are
# immutable - the same rule that forces pkgrel bumps on real recipes) and
# the publication succeeds: one owner per path.
rm -rf "$ownfix" "$stage/tar"
mkdir -p "$stage/tar/pkg/usr/bin"
printf '%s\n' tar > "$stage/tar/pkg/usr/bin/tar"
printf '%s\n' '{"arch":"x86_64","build_time":4,"license":"GPL-3.0-or-later","name":"tar","origin":"tar","outputs":[{"dependencies":[],"description":"tar","name":"tar","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/tar/","version":"1-r1"}' > "$stage/tar/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" tar >/dev/null
ownfix2=$incoming/ownfix2-ready
mkdir "$ownfix2"
cp "$artifacts/x86_64/tar-1-r1.apk" "$artifacts/x86_64/cpio-1-r0.apk" "$ownfix2/"
printf '%s\n' cpio > "$ownfix2/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$ownfix2/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"cpio","constructors":[{"constructor":"makepkg","producer":"cpio"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$ownfix2/artifact-manifest.json"
(CDPATH= cd -- "$ownfix2" && sha256sum tar-1-r1.apk cpio-1-r0.apk > manifest.sha256)
run_signer > "$test_root/ownfix2.out" 2> "$test_root/ownfix2.err"
test -f "$repo/tar-1-r1.apk"
test -f "$repo/cpio-1-r0.apk"
grep 'no file collisions' "$test_root/ownfix2.out" >/dev/null

# replaces= handover: a staged package may take over another name's paths
# (rename-with-ownership-takeover, e.g. expat replacing libexpat). tar2
# declares replaces=cpio and ships rmt: allowed, publishes.
mkdir -p "$stage/tar2/pkg/usr/libexec"
printf '%s\n' rmt > "$stage/tar2/pkg/usr/libexec/rmt"
printf '%s\n' '{"arch":"x86_64","build_time":5,"license":"GPL-3.0-or-later","name":"tar2","origin":"tar2","outputs":[{"dependencies":[],"description":"tar2","name":"tar2","payload":"pkg"}],"replaces":["cpio"],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"2-r0"}' > "$stage/tar2/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" tar2 >/dev/null
handover=$incoming/handover-ready
mkdir "$handover"
cp "$artifacts/x86_64/tar2-2-r0.apk" "$handover/"
printf '%s\n' tar2 > "$handover/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$handover/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"tar2","constructors":[{"constructor":"makepkg","producer":"tar2"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$handover/artifact-manifest.json"
(CDPATH= cd -- "$handover" && sha256sum tar2-2-r0.apk > manifest.sha256)
run_signer > "$test_root/handover.out" 2> "$test_root/handover.err"
test -f "$repo/tar2-2-r0.apk"

# Selective fast path: the full runs above warmed ownership.json, so a
# fresh solo package must publish through persisted state (assert the
# fresh marker, proving no full rescan ran). clash then shares a
# live-owned path (tar's binary, no replaces) and must refuse, still via
# the fast path - proving refusals don't need the full scan either.
mkdir -p "$stage/solo/pkg/usr/bin" "$stage/clash/pkg/usr/bin"
printf '%s\n' solo > "$stage/solo/pkg/usr/bin/solo"
printf '%s\n' tar > "$stage/clash/pkg/usr/bin/tar"
printf '%s\n' '{"arch":"x86_64","build_time":12,"license":"MIT","name":"solo","origin":"solo","outputs":[{"dependencies":[],"description":"solo","name":"solo","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/solo/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":13,"license":"MIT","name":"clash","origin":"clash","outputs":[{"dependencies":[],"description":"clash","name":"clash","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/clash/manifest.json"
for fixture in solo clash; do
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$fixture" >/dev/null
done
solo_txn=$incoming/solo-ready
mkdir "$solo_txn"
cp "$artifacts/x86_64/solo-1-r0.apk" "$solo_txn/"
printf '%s\n' solo > "$solo_txn/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$solo_txn/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"solo","constructors":[{"constructor":"makepkg","producer":"solo"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$solo_txn/artifact-manifest.json"
(CDPATH= cd -- "$solo_txn" && sha256sum solo-1-r0.apk > manifest.sha256)
run_signer solo > "$test_root/solo.out" 2> "$test_root/solo.err"
grep 'selective gate: ownership state fresh' "$test_root/solo.out" >/dev/null
test -f "$repo/solo-1-r0.apk"
test -f "$repo/ownership.json"
python3 - "$repo/ownership.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    state = json.load(stream)
assert state["schema"] == "saphira-ownership/v1"
assert ["solo", "1-r0"] in state["identities"]
assert state["newest"]["solo"] == "1-r0"
assert state["owners"]["usr/bin/solo"] == {"solo": "solo-1-r0"}
PY
clash_txn=$incoming/clash-ready
mkdir "$clash_txn"
cp "$artifacts/x86_64/clash-1-r0.apk" "$clash_txn/"
printf '%s\n' clash > "$clash_txn/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$clash_txn/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"clash","constructors":[{"constructor":"makepkg","producer":"clash"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$clash_txn/artifact-manifest.json"
(CDPATH= cd -- "$clash_txn" && sha256sum clash-1-r0.apk > manifest.sha256)
if run_signer clash > "$test_root/clash.out" 2> "$test_root/clash.err"; then
	printf '%s\n' 'fast-path collision unexpectedly published' >&2
	exit 1
fi
grep 'file ownership collision' "$test_root/clash.err" >/dev/null
grep 'usr/bin/tar' "$test_root/clash.err" >/dev/null
grep 'selective gate: ownership state fresh' "$test_root/clash.out" >/dev/null
test ! -f "$repo/clash-1-r0.apk"
# The correctly-refused transaction is discarded so later full runs are
# not blocked by it (same pattern as the ownfix collision fixture).
rm -rf "$clash_txn"

# Stale-state fallback: a present-but-wrong ownership.json (solo identity
# surgically removed) forces the selective run down the exit-9 path into
# a full rescan, which heals by republishing and rewriting state.
python3 - "$repo/ownership.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    state = json.load(stream)
state["identities"] = [i for i in state["identities"] if i[0] != "solo"]
with open(path, "w", encoding="utf-8") as stream:
    json.dump(state, stream)
    stream.write("\n")
PY
mkdir -p "$stage/lone/pkg/usr/bin"
printf '%s\n' lone > "$stage/lone/pkg/usr/bin/lone"
printf '%s\n' '{"arch":"x86_64","build_time":14,"license":"MIT","name":"lone","origin":"lone","outputs":[{"dependencies":[],"description":"lone","name":"lone","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/lone/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" lone >/dev/null
lone_txn=$incoming/lone-ready
mkdir "$lone_txn"
cp "$artifacts/x86_64/lone-1-r0.apk" "$lone_txn/"
printf '%s\n' lone > "$lone_txn/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$lone_txn/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"lone","constructors":[{"constructor":"makepkg","producer":"lone"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$lone_txn/artifact-manifest.json"
(CDPATH= cd -- "$lone_txn" && sha256sum lone-1-r0.apk > manifest.sha256)
run_signer lone > "$test_root/lone.out" 2> "$test_root/lone.err"
grep 'full rescan' "$test_root/lone.out" >/dev/null
test -f "$repo/lone-1-r0.apk"
python3 - "$repo/ownership.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    state = json.load(stream)
assert state["schema"] == "saphira-ownership/v1"
assert ["solo", "1-r0"] in state["identities"]
assert ["lone", "1-r0"] in state["identities"]
PY

# Legacy-dirt exemption: the gate only refuses paths present in a STAGED
# artifact. oldown r0 ships a shared path (published alone, single owner);
# midown r0 ships the same path and is hand-placed into the repository to
# simulate pre-gate archive dirt (both shell primitives, no fixture overlap
# with the tar/cpio cases above). When oldown r1 drops the path, its
# publication must succeed: nothing new enters, even though the staged NAME
# still co-owns the path via its superseded archive version.
mkdir -p "$stage/oldown/pkg/usr/libexec" "$stage/oldown/pkg/usr/bin" "$stage/midown/pkg/usr/libexec" "$stage/midown/pkg/usr/bin"
printf '%s\n' shared > "$stage/oldown/pkg/usr/libexec/shared"
printf '%s\n' oldown > "$stage/oldown/pkg/usr/bin/oldown"
printf '%s\n' shared > "$stage/midown/pkg/usr/libexec/shared"
printf '%s\n' midown > "$stage/midown/pkg/usr/bin/midown"
printf '%s\n' '{"arch":"x86_64","build_time":6,"license":"MIT","name":"oldown","origin":"oldown","outputs":[{"dependencies":[],"description":"oldown","name":"oldown","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/oldown/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":6,"license":"MIT","name":"midown","origin":"midown","outputs":[{"dependencies":[],"description":"midown","name":"midown","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/midown/manifest.json"
for fixture in oldown midown; do
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$fixture" >/dev/null
done
dirt=$incoming/dirt-ready
mkdir "$dirt"
cp "$artifacts/x86_64/oldown-1-r0.apk" "$dirt/"
printf '%s\n' oldown > "$dirt/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$dirt/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"oldown","constructors":[{"constructor":"makepkg","producer":"oldown"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$dirt/artifact-manifest.json"
(CDPATH= cd -- "$dirt" && sha256sum oldown-1-r0.apk > manifest.sha256)
run_signer > "$test_root/dirt.out" 2> "$test_root/dirt.err"
test -f "$repo/oldown-1-r0.apk"
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$artifacts/x86_64/midown-1-r0.apk"
cp "$artifacts/x86_64/midown-1-r0.apk" "$repo/midown-1-r0.apk"
rm -rf "$stage/oldown"
mkdir -p "$stage/oldown/pkg/usr/bin"
printf '%s\n' oldown > "$stage/oldown/pkg/usr/bin/oldown"
printf '%s\n' '{"arch":"x86_64","build_time":7,"license":"MIT","name":"oldown","origin":"oldown","outputs":[{"dependencies":[],"description":"oldown","name":"oldown","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/oldown/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" oldown >/dev/null
dirt2=$incoming/dirt2-ready
mkdir "$dirt2"
cp "$artifacts/x86_64/oldown-1-r1.apk" "$dirt2/"
printf '%s\n' oldown > "$dirt2/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$dirt2/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"oldown","constructors":[{"constructor":"makepkg","producer":"oldown"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$dirt2/artifact-manifest.json"
(CDPATH= cd -- "$dirt2" && sha256sum oldown-1-r1.apk > manifest.sha256)
run_signer > "$test_root/dirt2.out" 2> "$test_root/dirt2.err"
test -f "$repo/oldown-1-r1.apk"
grep 'no file collisions' "$test_root/dirt2.out" >/dev/null

# Newest-NVR ownership: superseded historical NVRs are archive history,
# not ownership competitors. senior r0 ships a shared path and publishes;
# senior r1 drops it and is hand-placed, so the archive holds both NVRs
# with current = r1 (no path). A staged junior r0 claiming that path must
# publish: the only live claimant is junior itself. Control: elder r0 is
# hand-placed KEEPING the path (sole, current NVR) while staged youngster
# r0 claims it - that must still refuse, proving the gate is not weakened
# for current owners.
mkdir -p "$stage/senior/pkg/usr/sbin" "$stage/senior/pkg/usr/bin" "$stage/junior/pkg/usr/sbin" "$stage/junior/pkg/usr/bin"
printf '%s\n' shared > "$stage/senior/pkg/usr/sbin/shared"
printf '%s\n' senior > "$stage/senior/pkg/usr/bin/senior"
printf '%s\n' shared > "$stage/junior/pkg/usr/sbin/shared"
printf '%s\n' junior > "$stage/junior/pkg/usr/bin/junior"
printf '%s\n' '{"arch":"x86_64","build_time":8,"license":"MIT","name":"senior","origin":"senior","outputs":[{"dependencies":[],"description":"senior","name":"senior","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/senior/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":8,"license":"MIT","name":"junior","origin":"junior","outputs":[{"dependencies":[],"description":"junior","name":"junior","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/junior/manifest.json"
for fixture in senior junior; do
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$fixture" >/dev/null
done
seniorpub=$incoming/seniorpub-ready
mkdir "$seniorpub"
cp "$artifacts/x86_64/senior-1-r0.apk" "$seniorpub/"
printf '%s\n' senior > "$seniorpub/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$seniorpub/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"senior","constructors":[{"constructor":"makepkg","producer":"senior"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$seniorpub/artifact-manifest.json"
(CDPATH= cd -- "$seniorpub" && sha256sum senior-1-r0.apk > manifest.sha256)
run_signer > "$test_root/seniorpub.out" 2> "$test_root/seniorpub.err"
test -f "$repo/senior-1-r0.apk"
rm -rf "$stage/senior"
mkdir -p "$stage/senior/pkg/usr/bin"
printf '%s\n' senior > "$stage/senior/pkg/usr/bin/senior"
printf '%s\n' '{"arch":"x86_64","build_time":9,"license":"MIT","name":"senior","origin":"senior","outputs":[{"dependencies":[],"description":"senior","name":"senior","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/senior/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" senior >/dev/null
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$artifacts/x86_64/senior-1-r1.apk"
cp "$artifacts/x86_64/senior-1-r1.apk" "$repo/senior-1-r1.apk"
juniorpub=$incoming/juniorpub-ready
mkdir "$juniorpub"
cp "$artifacts/x86_64/junior-1-r0.apk" "$juniorpub/"
printf '%s\n' junior > "$juniorpub/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$juniorpub/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"junior","constructors":[{"constructor":"makepkg","producer":"junior"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$juniorpub/artifact-manifest.json"
(CDPATH= cd -- "$juniorpub" && sha256sum junior-1-r0.apk > manifest.sha256)
run_signer > "$test_root/juniorpub.out" 2> "$test_root/juniorpub.err"
test -f "$repo/junior-1-r0.apk"
grep 'no file collisions' "$test_root/juniorpub.out" >/dev/null
mkdir -p "$stage/elder/pkg/usr/sbin" "$stage/elder/pkg/usr/bin" "$stage/youngster/pkg/usr/sbin" "$stage/youngster/pkg/usr/bin"
printf '%s\n' shared > "$stage/elder/pkg/usr/sbin/shared"
printf '%s\n' elder > "$stage/elder/pkg/usr/bin/elder"
printf '%s\n' shared > "$stage/youngster/pkg/usr/sbin/shared"
printf '%s\n' youngster > "$stage/youngster/pkg/usr/bin/youngster"
printf '%s\n' '{"arch":"x86_64","build_time":10,"license":"MIT","name":"elder","origin":"elder","outputs":[{"dependencies":[],"description":"elder","name":"elder","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/elder/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":11,"license":"MIT","name":"youngster","origin":"youngster","outputs":[{"dependencies":[],"description":"youngster","name":"youngster","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/youngster/manifest.json"
for fixture in elder youngster; do
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$fixture" >/dev/null
done
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$artifacts/x86_64/elder-1-r0.apk"
cp "$artifacts/x86_64/elder-1-r0.apk" "$repo/elder-1-r0.apk"
youngsterpub=$incoming/youngsterpub-ready
mkdir "$youngsterpub"
cp "$artifacts/x86_64/youngster-1-r0.apk" "$youngsterpub/"
printf '%s\n' youngster > "$youngsterpub/target"
printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$youngsterpub/bootstrap-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"youngster","constructors":[{"constructor":"makepkg","producer":"youngster"}],"bootstrap_seed":{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}}' > "$youngsterpub/artifact-manifest.json"
(CDPATH= cd -- "$youngsterpub" && sha256sum youngster-1-r0.apk > manifest.sha256)
if run_signer > "$test_root/youngsterpub.out" 2> "$test_root/youngsterpub.err"; then
	printf '%s\n' 'current-owner collision unexpectedly published' >&2
	exit 1
fi
grep 'file ownership collision' "$test_root/youngsterpub.err" >/dev/null
grep 'usr/sbin/shared' "$test_root/youngsterpub.err" >/dev/null
test ! -f "$repo/youngster-1-r0.apk"

printf '%s\n' 'privileged ready-transaction publication, identity, immutability, automatic pure-rebuild retirement, mixed-transaction refusal, ownership-collision gate, replaces-handover, legacy-dirt exemption, newest-NVR ownership, and selective fast-path tests: OK'

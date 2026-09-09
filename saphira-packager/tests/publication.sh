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

# SQLite era: repository metadata lives in repository.db, created here
# empty (the test genesis, mirroring what seed-repo does in
# production). Bare signing never creates repository metadata: without
# this step the first run below would refuse with a migration pointer.
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"make","constructors":[{"constructor":"makepkg","producer":"make"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$ready/artifact-manifest.json"
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
cp "$incoming/make-fixture-published"/{target,artifact-manifest.json,package-seed.json} "$conflict/"
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
cp "$incoming/make-fixture-published"/{target,artifact-manifest.json,package-seed.json} "$mixed/"
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
cp "$incoming/make-fixture-published/package-seed.json" "$incoming/ghost-fixture-ready/"
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
init_repo_db "$test_root/repository/hatched/x86_64" hatched
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$dual/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"gawk","constructors":[{"constructor":"makepkg","producer":"gawk"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$dual/artifact-manifest.json"
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
cp "$incoming/gawk-fixture-published/package-seed.json" "$div/"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"mawk","constructors":[{"constructor":"makepkg","producer":"mawk"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$div/artifact-manifest.json"
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$ownfix/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"cpio","constructors":[{"constructor":"makepkg","producer":"cpio"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$ownfix/artifact-manifest.json"
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$ownfix2/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"cpio","constructors":[{"constructor":"makepkg","producer":"cpio"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$ownfix2/artifact-manifest.json"
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$handover/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"tar2","constructors":[{"constructor":"makepkg","producer":"tar2"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$handover/artifact-manifest.json"
(CDPATH= cd -- "$handover" && sha256sum tar2-2-r0.apk > manifest.sha256)
run_signer > "$test_root/handover.out" 2> "$test_root/handover.err"
test -f "$repo/tar2-2-r0.apk"

# Selective fast path: the full runs above warmed repository.db, so a
# fresh solo package must publish through indexed rows (assert the
# fresh marker, proving no full audit ran). clash then shares a
# live-owned path (tar's binary, no replaces) and must refuse, still via
# the fast path - proving refusals don't need the full audit either.
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$solo_txn/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"solo","constructors":[{"constructor":"makepkg","producer":"solo"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$solo_txn/artifact-manifest.json"
(CDPATH= cd -- "$solo_txn" && sha256sum solo-1-r0.apk > manifest.sha256)
run_signer solo > "$test_root/solo.out" 2> "$test_root/solo.err"
grep 'selective gate: repository state fresh' "$test_root/solo.out" >/dev/null
grep 'staged gate:' "$test_root/solo.out" >/dev/null
test -f "$repo/solo-1-r0.apk"
test -f "$repo/repository.db"
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
idents = {(r[0], r[1]) for r in conn.execute("SELECT name, version FROM packages")}
assert ("solo", "1-r0") in idents
assert conn.execute("SELECT version FROM packages WHERE name='solo' AND is_newest=1").fetchone()[0] == "1-r0"
owners = {}
for pid, name, version in conn.execute(
        "SELECT package_id, name, version FROM packages WHERE is_newest=1"):
    for (path,) in conn.execute("SELECT path FROM files WHERE package_id=?", (pid,)):
        owners.setdefault(path, {})[name] = f"{name}-{version}"
assert owners["usr/bin/solo"] == {"solo": "solo-1-r0"}
PY

# Long-path folding: apk adbdump emits overlong dir names as YAML
# literal blocks ("- name: |" + continuation). The gate must unfold
# them: before the fix, every file under such a dir was keyed "|/<file>"
# (phantom collisions hiding the real directory). Ship a >100-char dir
# so the fold triggers, publish through the fast gate, then assert the
# owners map holds the real long path and no pipe-prefixed keys.
longdir=usr/lib/longfold-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$stage/longpath/pkg/$longdir"
printf '%s\n' deep > "$stage/longpath/pkg/$longdir/deep.h"
printf '%s\n' '{"arch":"x86_64","build_time":15,"license":"MIT","name":"longpath","origin":"longpath","outputs":[{"dependencies":[],"description":"longpath","name":"longpath","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/longpath/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" longpath >/dev/null
longpath_txn=$incoming/longpath-ready
mkdir "$longpath_txn"
cp "$artifacts/x86_64/longpath-1-r0.apk" "$longpath_txn/"
printf '%s\n' longpath > "$longpath_txn/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$longpath_txn/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"longpath","constructors":[{"constructor":"makepkg","producer":"longpath"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$longpath_txn/artifact-manifest.json"
(CDPATH= cd -- "$longpath_txn" && sha256sum longpath-1-r0.apk > manifest.sha256)
run_signer longpath > "$test_root/longpath.out" 2> "$test_root/longpath.err"
grep 'selective gate: repository state fresh' "$test_root/longpath.out" >/dev/null
test -f "$repo/longpath-1-r0.apk"
python3 - "$repo/repository.db" "$longdir/deep.h" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
owners = {}
for pid, name, version in conn.execute(
        "SELECT package_id, name, version FROM packages WHERE is_newest=1"):
    for (path,) in conn.execute("SELECT path FROM files WHERE package_id=?", (pid,)):
        owners.setdefault(path, {})[name] = f"{name}-{version}"
assert not [p for p in owners if p.startswith("|") or "/|/" in p], "pipe-prefixed phantom keys present"
assert owners[sys.argv[2]] == {"longpath": "longpath-1-r0"}
PY
clash_txn=$incoming/clash-ready
mkdir "$clash_txn"
cp "$artifacts/x86_64/clash-1-r0.apk" "$clash_txn/"
printf '%s\n' clash > "$clash_txn/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$clash_txn/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"clash","constructors":[{"constructor":"makepkg","producer":"clash"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$clash_txn/artifact-manifest.json"
(CDPATH= cd -- "$clash_txn" && sha256sum clash-1-r0.apk > manifest.sha256)
if run_signer clash > "$test_root/clash.out" 2> "$test_root/clash.err"; then
	printf '%s\n' 'fast-path collision unexpectedly published' >&2
	exit 1
fi
grep 'file ownership collision' "$test_root/clash.err" >/dev/null
grep 'usr/bin/tar' "$test_root/clash.err" >/dev/null
grep 'selective gate: repository state fresh' "$test_root/clash.out" >/dev/null
test ! -f "$repo/clash-1-r0.apk"
# The correctly-refused transaction is discarded so later full runs are
# not blocked by it (same pattern as the ownfix collision fixture).
rm -rf "$clash_txn"

# Stale-state fallback: a database missing a published identity forces
# the selective run down the exit-9 path into a full audit, which heals
# by reconciling (re-adding the row) and continuing to publish.
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
pid = conn.execute("SELECT package_id FROM packages WHERE name='solo'").fetchone()[0]
conn.execute("DELETE FROM files WHERE package_id=?", (pid,))
conn.execute("DELETE FROM packages WHERE package_id=?", (pid,))
conn.commit()
conn.close()
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$lone_txn/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"lone","constructors":[{"constructor":"makepkg","producer":"lone"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$lone_txn/artifact-manifest.json"
(CDPATH= cd -- "$lone_txn" && sha256sum lone-1-r0.apk > manifest.sha256)
run_signer lone > "$test_root/lone.out" 2> "$test_root/lone.err"
grep 'full audit' "$test_root/lone.out" >/dev/null
test -f "$repo/lone-1-r0.apk"
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
idents = {(r[0], r[1]) for r in conn.execute("SELECT name, version FROM packages")}
assert ("solo", "1-r0") in idents
assert ("lone", "1-r0") in idents
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$dirt/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"oldown","constructors":[{"constructor":"makepkg","producer":"oldown"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$dirt/artifact-manifest.json"
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$dirt2/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"oldown","constructors":[{"constructor":"makepkg","producer":"oldown"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$dirt2/artifact-manifest.json"
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$seniorpub/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"senior","constructors":[{"constructor":"makepkg","producer":"senior"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$seniorpub/artifact-manifest.json"
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
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$juniorpub/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"junior","constructors":[{"constructor":"makepkg","producer":"junior"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$juniorpub/artifact-manifest.json"
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
# Account identity gate: the global authority is the TSV reservation map
# plus every published accounts.d fragment. A staged package declaring
# a fresh identity publishes and registers it; a staged UID collision
# or a TSV redeclaration refuses publication with nothing mutated.
printf '%s\n' '# name	type	id	primary-group	home	shell	supplementary-groups' 'root	user	0	root	/root	/bin/bash	wheel' 'root	group	0	-	-	-	-' 'man	group	13	-	-	-	-' > "$test_root/accounts.tsv"
mkdir -p "$stage/acctsvc/pkg/usr/bin" "$stage/acctsvc/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctsvc > "$stage/acctsvc/pkg/usr/bin/acctsvc"
printf '%s\n' 'user acctuser 670 acctgroup /var/lib/acctsvc /sbin/nologin' 'group acctgroup 670' 'dir /var/lib/acctsvc 0755 acctuser acctgroup' > "$stage/acctsvc/pkg/usr/share/saphira/accounts.d/acctsvc"
printf '%s\n' '{"arch":"x86_64","build_time":10,"license":"MIT","name":"acctsvc","origin":"acctsvc","outputs":[{"dependencies":[],"description":"acctsvc","name":"acctsvc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctsvc/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctsvc >/dev/null
acctpub=$incoming/acctpub-ready
mkdir "$acctpub"
cp "$artifacts/x86_64/acctsvc-1-r0.apk" "$acctpub/"
printf '%s\n' acctsvc > "$acctpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$acctpub/package-seed.json"
acctsha=$(sha256sum "$acctpub/acctsvc-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctsvc","constructors":[{"constructor":"makepkg","producer":"acctsvc","artifacts":[{"name":"acctsvc","artifact":"acctsvc-1-r0.apk","sha256":"'"$acctsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"acctuser","uid":"670","primary":"acctgroup","home":"/var/lib/acctsvc","shell":"/sbin/nologin"}],"groups":[{"name":"acctgroup","gid":"670"}],"dirs":[{"path":"/var/lib/acctsvc","mode":"0755","owner":"acctuser","group":"acctgroup"}]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$acctpub/artifact-manifest.json"
(CDPATH= cd -- "$acctpub" && sha256sum acctsvc-1-r0.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/acctpub.out" 2> "$test_root/acctpub.err"
test -f "$repo/acctsvc-1-r0.apk"
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
row = conn.execute("SELECT numeric_id, owning_package, status FROM reservations"
                   " WHERE kind='user' AND name='acctuser'").fetchone()
assert row is not None and row[0] == 670 and row[1] == "acctsvc" and row[2] == "ACTIVE", row
row = conn.execute("SELECT numeric_id, owning_package, status FROM reservations"
                   " WHERE kind='group' AND name='acctgroup'").fetchone()
assert row is not None and row[0] == 670 and row[1] == "acctsvc" and row[2] == "ACTIVE", row
pid = conn.execute("SELECT package_id FROM packages WHERE name='acctsvc'").fetchone()[0]
assert conn.execute("SELECT uid FROM users WHERE package_id=? AND name='acctuser'", (pid,)).fetchone()[0] == 670
assert conn.execute("SELECT gid FROM groups WHERE package_id=? AND name='acctgroup'", (pid,)).fetchone()[0] == 670
assert conn.execute("SELECT mode FROM state_dirs WHERE package_id=? AND path='/var/lib/acctsvc'", (pid,)).fetchone()[0] == "0755"
PY
grep 'staged gate:' "$test_root/acctpub.out" >/dev/null
# A later unrelated publication gates fast and carries the registry forward.
mkdir -p "$stage/acctplain/pkg/usr/bin"
printf '%s\n' acctplain > "$stage/acctplain/pkg/usr/bin/acctplain"
printf '%s\n' '{"arch":"x86_64","build_time":11,"license":"MIT","name":"acctplain","origin":"acctplain","outputs":[{"dependencies":[],"description":"acctplain","name":"acctplain","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctplain/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctplain >/dev/null
plainpub=$incoming/plainpub-ready
mkdir "$plainpub"
cp "$artifacts/x86_64/acctplain-1-r0.apk" "$plainpub/"
printf '%s\n' acctplain > "$plainpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$plainpub/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctplain","constructors":[{"constructor":"makepkg","producer":"acctplain"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$plainpub/artifact-manifest.json"
(CDPATH= cd -- "$plainpub" && sha256sum acctplain-1-r0.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/plainpub.out" 2> "$test_root/plainpub.err"
test -f "$repo/acctplain-1-r0.apk"
grep 'selective gate: repository state fresh' "$test_root/plainpub.out" >/dev/null
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
row = conn.execute("SELECT status FROM reservations WHERE kind='user' AND name='acctuser'").fetchone()
assert row is not None and row[0] == "ACTIVE", row
PY
# A staged UID collision with the registered identity refuses loudly.
mkdir -p "$stage/acctevil/pkg/usr/bin" "$stage/acctevil/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctevil > "$stage/acctevil/pkg/usr/bin/acctevil"
printf '%s\n' 'user eviluser 670 acctgroup /var/lib/acctevil /sbin/nologin' > "$stage/acctevil/pkg/usr/share/saphira/accounts.d/acctevil"
printf '%s\n' '{"arch":"x86_64","build_time":12,"license":"MIT","name":"acctevil","origin":"acctevil","outputs":[{"dependencies":[],"description":"acctevil","name":"acctevil","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctevil/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctevil >/dev/null
evilpub=$incoming/evilpub-ready
mkdir "$evilpub"
cp "$artifacts/x86_64/acctevil-1-r0.apk" "$evilpub/"
printf '%s\n' acctevil > "$evilpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$evilpub/package-seed.json"
evilsha=$(sha256sum "$evilpub/acctevil-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctevil","constructors":[{"constructor":"makepkg","producer":"acctevil","artifacts":[{"name":"acctevil","artifact":"acctevil-1-r0.apk","sha256":"'"$evilsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"eviluser","uid":"670","primary":"acctgroup","home":"/var/lib/acctevil","shell":"/sbin/nologin"}],"groups":[],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$evilpub/artifact-manifest.json"
(CDPATH= cd -- "$evilpub" && sha256sum acctevil-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/evilpub.out" 2> "$test_root/evilpub.err"; then
	printf '%s\n' 'colliding account identity unexpectedly published' >&2
	exit 1
fi
grep 'account identity collision' "$test_root/evilpub.err" >/dev/null
test ! -f "$repo/acctevil-1-r0.apk"
mv "$evilpub" "$evilpub.superseded-conflict"
# Redeclaring a base-seed identity with IDENTICAL attributes converges
# and publishes (fresh images already carry it from assembly, older
# images gain it at install - both paths no-op safely).
mkdir -p "$stage/accttsv/pkg/usr/bin" "$stage/accttsv/pkg/usr/share/saphira/accounts.d"
printf '%s\n' accttsv > "$stage/accttsv/pkg/usr/bin/accttsv"
printf '%s\n' 'group man 13' > "$stage/accttsv/pkg/usr/share/saphira/accounts.d/accttsv"
printf '%s\n' '{"arch":"x86_64","build_time":13,"license":"MIT","name":"accttsv","origin":"accttsv","outputs":[{"dependencies":[],"description":"accttsv","name":"accttsv","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/accttsv/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" accttsv >/dev/null
tsvpub=$incoming/tsvpub-ready
mkdir "$tsvpub"
cp "$artifacts/x86_64/accttsv-1-r0.apk" "$tsvpub/"
printf '%s\n' accttsv > "$tsvpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$tsvpub/package-seed.json"
tsvsha=$(sha256sum "$tsvpub/accttsv-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"accttsv","constructors":[{"constructor":"makepkg","producer":"accttsv","artifacts":[{"name":"accttsv","artifact":"accttsv-1-r0.apk","sha256":"'"$tsvsha"'","backend":"userns-maproot","accounts":{"users":[],"groups":[{"name":"man","gid":"13"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$tsvpub/artifact-manifest.json"
(CDPATH= cd -- "$tsvpub" && sha256sum accttsv-1-r0.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/tsvpub.out" 2> "$test_root/tsvpub.err"
test -f "$repo/accttsv-1-r0.apk"
grep 'staged gate:' "$test_root/tsvpub.out" >/dev/null
# A redeclaration CONFLICTING with the base seed (same name, other GID)
# refuses just as loudly as a fragment collision.
mkdir -p "$stage/acctclash/pkg/usr/bin" "$stage/acctclash/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctclash > "$stage/acctclash/pkg/usr/bin/acctclash"
printf '%s\n' 'group man 14' > "$stage/acctclash/pkg/usr/share/saphira/accounts.d/acctclash"
printf '%s\n' '{"arch":"x86_64","build_time":14,"license":"MIT","name":"acctclash","origin":"acctclash","outputs":[{"dependencies":[],"description":"acctclash","name":"acctclash","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctclash/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctclash >/dev/null
clashpub=$incoming/clashpub-ready
mkdir "$clashpub"
cp "$artifacts/x86_64/acctclash-1-r0.apk" "$clashpub/"
printf '%s\n' acctclash > "$clashpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$clashpub/package-seed.json"
clashsha=$(sha256sum "$clashpub/acctclash-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctclash","constructors":[{"constructor":"makepkg","producer":"acctclash","artifacts":[{"name":"acctclash","artifact":"acctclash-1-r0.apk","sha256":"'"$clashsha"'","backend":"userns-maproot","accounts":{"users":[],"groups":[{"name":"man","gid":"14"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$clashpub/artifact-manifest.json"
(CDPATH= cd -- "$clashpub" && sha256sum acctclash-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/clashpub.out" 2> "$test_root/clashpub.err"; then
	printf '%s\n' 'base-seed-conflicting identity unexpectedly published' >&2
	exit 1
fi
grep 'conflicts with base seed' "$test_root/clashpub.err" >/dev/null
test ! -f "$repo/acctclash-1-r0.apk"
mv "$clashpub" "$clashpub.superseded-conflict"
# An identity outside the packaged range (888..999 local, 1000+ human)
# refuses at the publish backstop even with a crafted receipt. (The APK
# ships a valid fragment so the receipt/fragment presence checks pass
# and the range rule itself is what fires - makepkg would never build
# an out-of-range fragment, so the receipt is the gate's input here.)
mkdir -p "$stage/acctrange/pkg/usr/bin" "$stage/acctrange/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctrange > "$stage/acctrange/pkg/usr/bin/acctrange"
printf '%s\n' 'user rangeuser 671 rangegroup /var/lib/range /sbin/nologin' 'group rangegroup 671' > "$stage/acctrange/pkg/usr/share/saphira/accounts.d/acctrange"
printf '%s\n' '{"arch":"x86_64","build_time":15,"license":"MIT","name":"acctrange","origin":"acctrange","outputs":[{"dependencies":[],"description":"acctrange","name":"acctrange","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctrange/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctrange >/dev/null
rangepub=$incoming/rangepub-ready
mkdir "$rangepub"
cp "$artifacts/x86_64/acctrange-1-r0.apk" "$rangepub/"
printf '%s\n' acctrange > "$rangepub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$rangepub/package-seed.json"
rangesha=$(sha256sum "$rangepub/acctrange-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctrange","constructors":[{"constructor":"makepkg","producer":"acctrange","artifacts":[{"name":"acctrange","artifact":"acctrange-1-r0.apk","sha256":"'"$rangesha"'","backend":"userns-maproot","accounts":{"users":[{"name":"rangeuser","uid":"900","primary":"rangegroup","home":"/var/lib/range","shell":"/sbin/nologin"}],"groups":[{"name":"rangegroup","gid":"900"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$rangepub/artifact-manifest.json"
(CDPATH= cd -- "$rangepub" && sha256sum acctrange-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/rangepub.out" 2> "$test_root/rangepub.err"; then
	printf '%s\n' 'out-of-range identity unexpectedly published' >&2
	exit 1
fi
grep 'outside the packaged range 0..887' "$test_root/rangepub.err" >/dev/null
test ! -f "$repo/acctrange-1-r0.apk"
mv "$rangepub" "$rangepub.superseded-conflict"
# An identity in the 200..887 expansion range publishes with a loud
# notice (the fragment must document the exception).
mkdir -p "$stage/acctmid/pkg/usr/bin" "$stage/acctmid/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctmid > "$stage/acctmid/pkg/usr/bin/acctmid"
printf '%s\n' '# documented exception fixture' 'user miduser 250 midgroup /var/lib/acctmid /sbin/nologin' 'group midgroup 250' > "$stage/acctmid/pkg/usr/share/saphira/accounts.d/acctmid"
printf '%s\n' '{"arch":"x86_64","build_time":16,"license":"MIT","name":"acctmid","origin":"acctmid","outputs":[{"dependencies":[],"description":"acctmid","name":"acctmid","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctmid/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctmid >/dev/null
midpub=$incoming/midpub-ready
mkdir "$midpub"
cp "$artifacts/x86_64/acctmid-1-r0.apk" "$midpub/"
printf '%s\n' acctmid > "$midpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$midpub/package-seed.json"
midsha=$(sha256sum "$midpub/acctmid-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctmid","constructors":[{"constructor":"makepkg","producer":"acctmid","artifacts":[{"name":"acctmid","artifact":"acctmid-1-r0.apk","sha256":"'"$midsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"miduser","uid":"250","primary":"midgroup","home":"/var/lib/acctmid","shell":"/sbin/nologin"}],"groups":[{"name":"midgroup","gid":"250"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$midpub/artifact-manifest.json"
(CDPATH= cd -- "$midpub" && sha256sum acctmid-1-r0.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/midpub.out" 2> "$test_root/midpub.err"
test -f "$repo/acctmid-1-r0.apk"
grep 'expansion range' "$test_root/midpub.out" >/dev/null
# A crafted receipt declaring a reserved identity (root) refuses at
# the publish backstop even though the APK itself is well-formed:
# makepkg would never build such a fragment, so the receipt is the
# gate's input here (same shape as the range-backstop case above).
mkdir -p "$stage/acctroot/pkg/usr/bin" "$stage/acctroot/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctroot > "$stage/acctroot/pkg/usr/bin/acctroot"
printf '%s\n' 'user rootuser 671 rootgroup /var/lib/acctroot /sbin/nologin' 'group rootgroup 671' > "$stage/acctroot/pkg/usr/share/saphira/accounts.d/acctroot"
printf '%s\n' '{"arch":"x86_64","build_time":17,"license":"MIT","name":"acctroot","origin":"acctroot","outputs":[{"dependencies":[],"description":"acctroot","name":"acctroot","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctroot/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctroot >/dev/null
rootpub=$incoming/rootpub-ready
mkdir "$rootpub"
cp "$artifacts/x86_64/acctroot-1-r0.apk" "$rootpub/"
printf '%s\n' acctroot > "$rootpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$rootpub/package-seed.json"
rootsha=$(sha256sum "$rootpub/acctroot-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctroot","constructors":[{"constructor":"makepkg","producer":"acctroot","artifacts":[{"name":"acctroot","artifact":"acctroot-1-r0.apk","sha256":"'"$rootsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"root","uid":"0","primary":"root","home":"/root","shell":"/bin/bash"}],"groups":[{"name":"root","gid":"0"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$rootpub/artifact-manifest.json"
(CDPATH= cd -- "$rootpub" && sha256sum acctroot-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/rootpub.out" 2> "$test_root/rootpub.err"; then
	printf '%s\n' 'reserved identity unexpectedly published' >&2
	exit 1
fi
grep 'reserved system identity' "$test_root/rootpub.err" >/dev/null
test ! -f "$repo/acctroot-1-r0.apk"
mv "$rootpub" "$rootpub.superseded-conflict"
# A crafted receipt claiming a foundational group (spokes:2) refuses
# the same way: the gate is typed by kind, not by name alone.
mkdir -p "$stage/acctspokes/pkg/usr/bin" "$stage/acctspokes/pkg/usr/share/saphira/accounts.d"
printf '%s\n' acctspokes > "$stage/acctspokes/pkg/usr/bin/acctspokes"
printf '%s\n' 'user spokeuser 672 spokegroup /var/lib/acctspokes /sbin/nologin' 'group spokegroup 672' > "$stage/acctspokes/pkg/usr/share/saphira/accounts.d/acctspokes"
printf '%s\n' '{"arch":"x86_64","build_time":18,"license":"MIT","name":"acctspokes","origin":"acctspokes","outputs":[{"dependencies":[],"description":"acctspokes","name":"acctspokes","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/acctspokes/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctspokes >/dev/null
spokespub=$incoming/spokespub-ready
mkdir "$spokespub"
cp "$artifacts/x86_64/acctspokes-1-r0.apk" "$spokespub/"
printf '%s\n' acctspokes > "$spokespub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$spokespub/package-seed.json"
spokessha=$(sha256sum "$spokespub/acctspokes-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctspokes","constructors":[{"constructor":"makepkg","producer":"acctspokes","artifacts":[{"name":"acctspokes","artifact":"acctspokes-1-r0.apk","sha256":"'"$spokessha"'","backend":"userns-maproot","accounts":{"users":[],"groups":[{"name":"spokes","gid":"2"}],"dirs":[]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$spokespub/artifact-manifest.json"
(CDPATH= cd -- "$spokespub" && sha256sum acctspokes-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/spokespub.out" 2> "$test_root/spokespub.err"; then
	printf '%s\n' 'foundation group unexpectedly published' >&2
	exit 1
fi
grep 'reserved foundation' "$test_root/spokespub.err" >/dev/null
test ! -f "$repo/acctspokes-1-r0.apk"
mv "$spokespub" "$spokespub.superseded-conflict"
printf '%s\n' 'account identity gate, ledger carry-forward, UID-collision, base-seed convergence/conflict, range refusal, reserved-identity refusal, and expansion-notice tests: OK'

youngsterpub=$incoming/youngsterpub-ready
mkdir "$youngsterpub"
cp "$artifacts/x86_64/youngster-1-r0.apk" "$youngsterpub/"
printf '%s\n' youngster > "$youngsterpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$youngsterpub/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"youngster","constructors":[{"constructor":"makepkg","producer":"youngster"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$youngsterpub/artifact-manifest.json"
(CDPATH= cd -- "$youngsterpub" && sha256sum youngster-1-r0.apk > manifest.sha256)
if run_signer > "$test_root/youngsterpub.out" 2> "$test_root/youngsterpub.err"; then
	printf '%s\n' 'current-owner collision unexpectedly published' >&2
	exit 1
fi
grep 'file ownership collision' "$test_root/youngsterpub.err" >/dev/null
grep 'usr/sbin/shared' "$test_root/youngsterpub.err" >/dev/null
test ! -f "$repo/youngster-1-r0.apk"

printf '%s\n' 'privileged ready-transaction publication, identity, immutability, automatic pure-rebuild retirement, mixed-transaction refusal, ownership-collision gate, replaces-handover, legacy-dirt exemption, newest-NVR ownership, and selective fast-path tests: OK'

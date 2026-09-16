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
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-publication-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
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
printf '%s\n' '{"arch":"x86_64","build_time":2,"license":"GPL-3.0-or-later","name":"gawk","origin":"gawk","outputs":[{"dependencies":[],"description":"GNU awk","name":"gawk","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://www.gnu.org/software/gawk/","version":"1-r1"}' > "$stage/gawk/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" gawk >/dev/null
dual=$incoming/gawk-fixture-ready
mkdir "$dual"
cp "$artifacts/x86_64/gawk-1-r1.apk" "$dual/"
printf '%s\n' gawk > "$dual/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$dual/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"gawk","constructors":[{"constructor":"makepkg","producer":"gawk"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$dual/artifact-manifest.json"
(CDPATH= cd -- "$dual" && sha256sum gawk-1-r1.apk > manifest.sha256)
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling hatched' \
	unshare --map-root-user "$sign_repo" >/dev/null
hatched_repo=$test_root/repository/hatched/x86_64
test -f "$hatched_repo/gawk-1-r1.apk"
test -f "$repo/gawk-1-r1.apk"
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
printf '%s\n' '{"arch":"x86_64","build_time":3,"license":"GPL-3.0-or-later","name":"mawk","origin":"mawk","outputs":[{"dependencies":[],"description":"minimal awk","name":"mawk","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/mawk/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" mawk >/dev/null
cp "$artifacts/x86_64/mawk-1-r1.apk" "$repo/"
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$repo/mawk-1-r1.apk"
div=$incoming/mawk-fixture-ready
mkdir "$div"
cp "$artifacts/x86_64/mawk-1-r1.apk" "$div/"
printf '%s\n' mawk > "$div/target"
cp "$incoming/gawk-fixture-published/package-seed.json" "$div/"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"mawk","constructors":[{"constructor":"makepkg","producer":"mawk"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$div/artifact-manifest.json"
(CDPATH= cd -- "$div" && sha256sum mawk-1-r1.apk > manifest.sha256)
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling hatched' \
	unshare --map-root-user "$sign_repo" >/dev/null
test -f "$hatched_repo/mawk-1-r1.apk"
test -f "$repo/mawk-1-r1.apk"
[ "$(apk adbdump "$repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 3 ]
[ "$(apk adbdump "$hatched_repo/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 2 ]
test -d "$incoming/mawk-fixture-published"

# r0 refusal at the publishing boundary: a staged r0 in a multi-generation
# run would land in the live view, so it dies before any mutation (resolvepkg
# and buildpkg-single refuse r0 upstream; this makes hand-crafted
# transactions fail closed too). Single-generation archive runs still take
# historical r0 fixtures elsewhere in this suite. m4-1-r0 was built above
# but never published, so it stages clean apart from its revision.
r0ban=$incoming/r0ban-fixture-ready
mkdir "$r0ban"
cp "$artifacts/x86_64/m4-1-r0.apk" "$r0ban/"
printf '%s\n' r0ban > "$r0ban/target"
cp "$incoming/make-fixture-published/package-seed.json" "$r0ban/"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"r0ban","constructors":[{"constructor":"makepkg","producer":"m4"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$r0ban/artifact-manifest.json"
(CDPATH= cd -- "$r0ban" && sha256sum m4-1-r0.apk > manifest.sha256)
r0ban_before=$(find "$test_root/repository" -type f -printf '%P %s\n' | sort | sha256sum)
if SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling hatched' \
	unshare --map-root-user "$sign_repo" r0ban > "$test_root/r0ban.out" 2> "$test_root/r0ban.err"; then
	printf '%s\n' 'r0 publication to a live generation unexpectedly succeeded' >&2
	exit 1
fi
grep 'r0 packages are forbidden' "$test_root/r0ban.err" >/dev/null
[ "$r0ban_before" = "$(find "$test_root/repository" -type f -printf '%P %s\n' | sort | sha256sum)" ]
rm -rf "$r0ban"

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

# Newer-or-novel abandonment: a file moving from a package to a sibling
# subpackage across revisions publishes clean. mvf r1 ships tool + .pc;
# r2 abandons the .pc to mvf-dev r2. Without the abandonment rule the
# stale published r1 claim would collide with mvf-dev forever.
mkdir -p "$stage/mvf/pkg/usr/bin" "$stage/mvf/pkg/usr/lib/pkgconfig"
printf '%s\n' tool > "$stage/mvf/pkg/usr/bin/tool"
printf '%s\n' pc > "$stage/mvf/pkg/usr/lib/pkgconfig/tool.pc"
printf '%s\n' '{"arch":"x86_64","build_time":6,"license":"MIT","name":"mvf","origin":"mvf","outputs":[{"dependencies":[],"description":"mvf","name":"mvf","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/mvf/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" mvf >/dev/null
movefix=$incoming/movefix-ready
mkdir "$movefix"
cp "$artifacts/x86_64/mvf-1-r1.apk" "$movefix/"
printf '%s\n' mvf > "$movefix/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$movefix/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"mvf","constructors":[{"constructor":"makepkg","producer":"mvf"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$movefix/artifact-manifest.json"
(CDPATH= cd -- "$movefix" && sha256sum mvf-1-r1.apk > manifest.sha256)
run_signer > "$test_root/movefix.out" 2> "$test_root/movefix.err"
test -f "$repo/mvf-1-r1.apk"
rm -rf "$stage/mvf"
mkdir -p "$stage/mvf/pkg/usr/bin"
printf '%s\n' tool > "$stage/mvf/pkg/usr/bin/tool"
printf '%s\n' '{"arch":"x86_64","build_time":7,"license":"MIT","name":"mvf","origin":"mvf","outputs":[{"dependencies":[],"description":"mvf","name":"mvf","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r2"}' > "$stage/mvf/manifest.json"
mkdir -p "$stage/mvfdev/pkg/usr/lib/pkgconfig"
printf '%s\n' pc > "$stage/mvfdev/pkg/usr/lib/pkgconfig/tool.pc"
printf '%s\n' '{"arch":"x86_64","build_time":8,"license":"MIT","name":"mvfdev","origin":"mvf","outputs":[{"dependencies":[],"description":"mvfdev","name":"mvfdev","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r2"}' > "$stage/mvfdev/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" mvf >/dev/null
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" mvfdev >/dev/null
movetxn=$incoming/move-ready
mkdir "$movetxn"
cp "$artifacts/x86_64/mvf-1-r2.apk" "$artifacts/x86_64/mvfdev-1-r2.apk" "$movetxn/"
printf '%s\n' mvf > "$movetxn/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$movetxn/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"mvf","constructors":[{"constructor":"makepkg","producer":"mvf"},{"constructor":"makepkg","producer":"mvfdev"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$movetxn/artifact-manifest.json"
(CDPATH= cd -- "$movetxn" && sha256sum mvf-1-r2.apk mvfdev-1-r2.apk > manifest.sha256)
run_signer > "$test_root/move.out" 2> "$test_root/move.err"
test -f "$repo/mvf-1-r2.apk"
test -f "$repo/mvfdev-1-r2.apk"
grep 'no file collisions' "$test_root/move.out" >/dev/null

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
# publish: the only live claimant is junior itself. Control: elder r1 is
# hand-placed KEEPING the path (sole, current, admissible NVR) while
# staged youngster r0 claims it - that must still refuse, proving the
# gate is not weakened for current owners. (An r0 newest is history,
# never a current owner under the r0-inadmissibility policy, so the
# control owner is r1: r0 claims never block anyone.)
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
printf '%s\n' '{"arch":"x86_64","build_time":10,"license":"MIT","name":"elder","origin":"elder","outputs":[{"dependencies":[],"description":"elder","name":"elder","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/elder/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":11,"license":"MIT","name":"youngster","origin":"youngster","outputs":[{"dependencies":[],"description":"youngster","name":"youngster","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/youngster/manifest.json"
for fixture in elder youngster; do
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$fixture" >/dev/null
done
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$artifacts/x86_64/elder-1-r1.apk"
cp "$artifacts/x86_64/elder-1-r1.apk" "$repo/elder-1-r1.apk"
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
# Same-name succession: upgrading an identity-declaring package supersedes
# its own repo declaration instead of colliding with it (regression: the
# SQLite gate once false-refused an upgrade as "claimed by r4 and staged
# r5"). The successor publishes, newest flips, the reservation stays owned.
printf '%s\n' '{"arch":"x86_64","build_time":10,"license":"MIT","name":"acctsvc","origin":"acctsvc","outputs":[{"dependencies":[],"description":"acctsvc","name":"acctsvc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/acctsvc/manifest.json"
rm -f "$stage/acctsvc/artifact-manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" acctsvc >/dev/null
succpub=$incoming/succpub-ready
mkdir "$succpub"
cp "$artifacts/x86_64/acctsvc-1-r1.apk" "$succpub/"
printf '%s\n' acctsvc > "$succpub/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$succpub/package-seed.json"
succsha=$(sha256sum "$succpub/acctsvc-1-r1.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"acctsvc","constructors":[{"constructor":"makepkg","producer":"acctsvc","artifacts":[{"name":"acctsvc","artifact":"acctsvc-1-r1.apk","sha256":"'"$succsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"acctuser","uid":"670","primary":"acctgroup","home":"/var/lib/acctsvc","shell":"/sbin/nologin"}],"groups":[{"name":"acctgroup","gid":"670"}],"dirs":[{"path":"/var/lib/acctsvc","mode":"0755","owner":"acctuser","group":"acctgroup"}]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$succpub/artifact-manifest.json"
(CDPATH= cd -- "$succpub" && sha256sum acctsvc-1-r1.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/succpub.out" 2> "$test_root/succpub.err"
test -f "$repo/acctsvc-1-r1.apk"
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
newest = conn.execute("SELECT version FROM packages WHERE name='acctsvc' AND is_newest=1").fetchall()
assert len(newest) == 1 and newest[0][0] == "1-r1", newest
row = conn.execute("SELECT owning_package, status FROM reservations"
                   " WHERE kind='user' AND name='acctuser'").fetchone()
assert row is not None and row[0] == "acctsvc" and row[1] == "ACTIVE", row
PY
grep 'staged gate:' "$test_root/succpub.out" >/dev/null
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
# File stanzas publish when every reference resolves to what the
# package owns plus the root built-in; a receipt claiming an
# undeclared owner refuses at the same backstop.
mkdir -p "$stage/filepub/pkg/usr/bin" "$stage/filepub/pkg/usr/share/saphira/accounts.d"
printf '%s\n' filepub > "$stage/filepub/pkg/usr/bin/filepub"
printf '%s\n' queuebinary > "$stage/filepub/pkg/usr/bin/filepub-queue"
printf '%s\n' 'user fileuser 673 filegroup /var/lib/filepub /sbin/nologin' 'group filegroup 673' 'file /usr/bin/filepub-queue 04711 fileuser filegroup' 'file /usr/bin/filepub 0755 root root' > "$stage/filepub/pkg/usr/share/saphira/accounts.d/filepub"
printf '%s\n' '{"arch":"x86_64","build_time":19,"license":"MIT","name":"filepub","origin":"filepub","outputs":[{"dependencies":[],"description":"filepub","name":"filepub","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/filepub/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" filepub >/dev/null
filepubdir=$incoming/filepub-ready
mkdir "$filepubdir"
cp "$artifacts/x86_64/filepub-1-r0.apk" "$filepubdir/"
printf '%s\n' filepub > "$filepubdir/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$filepubdir/package-seed.json"
filesha=$(sha256sum "$filepubdir/filepub-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"filepub","constructors":[{"constructor":"makepkg","producer":"filepub","artifacts":[{"name":"filepub","artifact":"filepub-1-r0.apk","sha256":"'"$filesha"'","backend":"userns-maproot","accounts":{"users":[{"name":"fileuser","uid":"673","primary":"filegroup","home":"/var/lib/filepub","shell":"/sbin/nologin"}],"groups":[{"name":"filegroup","gid":"673"}],"dirs":[],"files":[{"path":"/usr/bin/filepub-queue","mode":"04711","owner":"fileuser","group":"filegroup"},{"path":"/usr/bin/filepub","mode":"0755","owner":"root","group":"root"}]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$filepubdir/artifact-manifest.json"
(CDPATH= cd -- "$filepubdir" && sha256sum filepub-1-r0.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/filepub.out" 2> "$test_root/filepub.err"
test -f "$repo/filepub-1-r0.apk"
# A file stanza naming an owner the package does not declare builds
# fine (shape-valid, payload-bound) but refuses at publication: the
# gate is where references must resolve to owned-or-root identities.
mkdir -p "$stage/fileevil/pkg/usr/bin" "$stage/fileevil/pkg/usr/share/saphira/accounts.d"
printf '%s\n' fileevil > "$stage/fileevil/pkg/usr/bin/fileevil"
printf '%s\n' queuebinary > "$stage/fileevil/pkg/usr/bin/fileevil-queue"
printf '%s\n' 'user fileeviluser 674 fileevilgroup /var/lib/fileevil /sbin/nologin' 'group fileevilgroup 674' 'file /usr/bin/fileevil-queue 04711 ghostuser fileevilgroup' > "$stage/fileevil/pkg/usr/share/saphira/accounts.d/fileevil"
printf '%s\n' '{"arch":"x86_64","build_time":20,"license":"MIT","name":"fileevil","origin":"fileevil","outputs":[{"dependencies":[],"description":"fileevil","name":"fileevil","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/fileevil/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" fileevil >/dev/null
fileevil=$incoming/fileevil-ready
mkdir "$fileevil"
cp "$artifacts/x86_64/fileevil-1-r0.apk" "$fileevil/"
printf '%s\n' fileevil > "$fileevil/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$fileevil/package-seed.json"
evilsha=$(sha256sum "$fileevil/fileevil-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"fileevil","constructors":[{"constructor":"makepkg","producer":"fileevil","artifacts":[{"name":"fileevil","artifact":"fileevil-1-r0.apk","sha256":"'"$evilsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"fileeviluser","uid":"674","primary":"fileevilgroup","home":"/var/lib/fileevil","shell":"/sbin/nologin"}],"groups":[{"name":"fileevilgroup","gid":"674"}],"dirs":[],"files":[{"path":"/usr/bin/fileevil-queue","mode":"04711","owner":"ghostuser","group":"fileevilgroup"}]}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$fileevil/artifact-manifest.json"
(CDPATH= cd -- "$fileevil" && sha256sum fileevil-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/fileevil.out" 2> "$test_root/fileevil.err"; then
	printf '%s\n' 'undeclared file owner unexpectedly published' >&2
	exit 1
fi
grep 'file ownership references undeclared identities' "$test_root/fileevil.err" >/dev/null
test ! -f "$repo/fileevil-1-r0.apk"
mv "$fileevil" "$fileevil.superseded-conflict"
# Legacy history colliding with a declared present refuses: staged
# history naming the registered acctuser UID is ambiguous no matter
# which package claims the past.
mkdir -p "$stage/legacypub/pkg/usr/bin" "$stage/legacypub/pkg/usr/share/saphira/accounts.d"
printf '%s\n' legacypub > "$stage/legacypub/pkg/usr/bin/legacypub"
printf '%s\n' 'user legacyuser 674 legacygroup /var/lib/legacypub /sbin/nologin' 'group legacygroup 674' > "$stage/legacypub/pkg/usr/share/saphira/accounts.d/legacypub"
printf '%s\n' 'legacy user legacyuser 670 670' > "$stage/legacypub/pkg/usr/share/saphira/accounts.d/legacypub.legacy"
printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"legacypub","origin":"legacypub","outputs":[{"dependencies":[],"description":"legacypub","name":"legacypub","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/legacypub/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" legacypub >/dev/null
legacypubdir=$incoming/legacypub-ready
mkdir "$legacypubdir"
cp "$artifacts/x86_64/legacypub-1-r0.apk" "$legacypubdir/"
printf '%s\n' legacypub > "$legacypubdir/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$legacypubdir/package-seed.json"
legacysha=$(sha256sum "$legacypubdir/legacypub-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"legacypub","constructors":[{"constructor":"makepkg","producer":"legacypub","artifacts":[{"name":"legacypub","artifact":"legacypub-1-r0.apk","sha256":"'"$legacysha"'","backend":"userns-maproot","accounts":{"users":[{"name":"legacyuser","uid":"674","primary":"legacygroup","home":"/var/lib/legacypub","shell":"/sbin/nologin"}],"groups":[{"name":"legacygroup","gid":"674"}],"dirs":[],"files":[],"legacy":{"users":[{"name":"legacyuser","uid":"670","gid":"670"}],"groups":[]}}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$legacypubdir/artifact-manifest.json"
(CDPATH= cd -- "$legacypubdir" && sha256sum legacypub-1-r0.apk > manifest.sha256)
if SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/legacypub.out" 2> "$test_root/legacypub.err"; then
	printf '%s\n' 'colliding legacy history unexpectedly published' >&2
	exit 1
fi
grep 'legacy history collides with declared identities' "$test_root/legacypub.err" >/dev/null
test ! -f "$repo/legacypub-1-r0.apk"
mv "$legacypubdir" "$legacypubdir.superseded-conflict"
# Paired legacy history (user + primary group sharing one old ID, the
# universal Unix shape) publishes: the user's GID is a reference, not
# a second group-namespace claim, so the pair must not self-collide.
mkdir -p "$stage/legacypair/pkg/usr/bin" "$stage/legacypair/pkg/usr/share/saphira/accounts.d"
printf '%s\n' legacypair > "$stage/legacypair/pkg/usr/bin/legacypair"
printf '%s\n' 'user pairuser 676 pairgroup /var/lib/legacypair /sbin/nologin' 'group pairgroup 676' > "$stage/legacypair/pkg/usr/share/saphira/accounts.d/legacypair"
printf '%s\n' 'legacy user pairuser 675 675' 'legacy group pairgroup 675' > "$stage/legacypair/pkg/usr/share/saphira/accounts.d/legacypair.legacy"
printf '%s\n' '{"arch":"x86_64","build_time":22,"license":"MIT","name":"legacypair","origin":"legacypair","outputs":[{"dependencies":[],"description":"legacypair","name":"legacypair","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r0"}' > "$stage/legacypair/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" legacypair >/dev/null
legacypairdir=$incoming/legacypair-ready
mkdir "$legacypairdir"
cp "$artifacts/x86_64/legacypair-1-r0.apk" "$legacypairdir/"
printf '%s\n' legacypair > "$legacypairdir/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$legacypairdir/package-seed.json"
pairsha=$(sha256sum "$legacypairdir/legacypair-1-r0.apk" | awk '{ print $1 }')
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"legacypair","constructors":[{"constructor":"makepkg","producer":"legacypair","artifacts":[{"name":"legacypair","artifact":"legacypair-1-r0.apk","sha256":"'"$pairsha"'","backend":"userns-maproot","accounts":{"users":[{"name":"pairuser","uid":"676","primary":"pairgroup","home":"/var/lib/legacypair","shell":"/sbin/nologin"}],"groups":[{"name":"pairgroup","gid":"676"}],"dirs":[],"files":[],"legacy":{"users":[{"name":"pairuser","uid":"675","gid":"675"}],"groups":[{"name":"pairgroup","gid":"675"}]}}}]}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$legacypairdir/artifact-manifest.json"
(CDPATH= cd -- "$legacypairdir" && sha256sum legacypair-1-r0.apk > manifest.sha256)
SAPHIRA_ACCOUNTS_TSV=$test_root/accounts.tsv run_signer > "$test_root/legacypair.out" 2> "$test_root/legacypair.err"
test -f "$repo/legacypair-1-r0.apk"
printf '%s\n' 'account identity gate, ledger carry-forward, UID-collision, base-seed convergence/conflict, range refusal, reserved-identity refusal, file-reference accept/refusal, legacy-history refusal, paired-legacy acceptance, and expansion-notice tests: OK'

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

# Hatched retention: the live generation keeps the newest 2 NVRs per
# name; older NVRs retire inside the publication transaction unless a
# live dependent pins them or they sit on SAPHIRA_RETAIN_NVR. Archive
# generations never prune. Dual runs below target hatchling+hatched, so
# the live view is the hatched test repository.
run_signer_dual()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES='hatchling hatched' \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}
fixture_pkg()
{
	# fixture_pkg name version path content depjson
	# (re)builds one single-output producer; depjson is raw JSON
	# (e.g. '"foo=1.0-r1"' or empty).
	producer=$1 name=$2 version=$3 path=$4 content=$5 depjson=$6
	rm -rf "$stage/$producer"
	mkdir -p "$stage/$producer/pkg/$(dirname "$path")"
	printf '%s\n' "$content" > "$stage/$producer/pkg/$path"
	printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"'$producer'","origin":"'$name'","outputs":[{"dependencies":['$depjson'],"description":"'$name'","name":"'$name'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"'$version'"}' > "$stage/$producer/manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$producer" >/dev/null
}
stage_txn()
{
	# stage_txn txn-dir target producer apk...
	txn=$1 target=$2 producer=$3
	shift 3
	mkdir "$txn"
	for apk in "$@"; do
		cp "$artifacts/x86_64/$apk" "$txn/"
	done
	printf '%s\n' "$target" > "$txn/target"
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$txn/package-seed.json"
	printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"'$target'","constructors":[{"constructor":"makepkg","producer":"'$producer'"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$txn/artifact-manifest.json"
	(CDPATH= cd -- "$txn" && sha256sum "$@" > manifest.sha256)
}
live_has()
{
	# live_has <apk|nofile:apk>... : assert presence/absence in hatched files+index+db
	for want in "$@"; do
		case $want in
			nofile:*)
				f=${want#nofile:}
				test ! -e "$hatched_repo/$f" || return 1
				apk adbdump "$hatched_repo/Packages.adb" | grep -q "$f" && return 1 || true
				;;
			*)
				test -f "$hatched_repo/$want" || return 1
				;;
		esac
	done
}

# Rollback generations: third publish retires the oldest from live only.
fixture_pkg retfoo retfoo 1-r1 usr/bin/retfoo one ""
stage_txn "$incoming/retent1-ready" retfoo retfoo retfoo-1-r1.apk
run_signer_dual retfoo > "$test_root/retent1.out" 2> "$test_root/retent1.err"
fixture_pkg retfoo retfoo 1-r2 usr/bin/retfoo two ""
stage_txn "$incoming/retent2-ready" retfoo retfoo retfoo-1-r2.apk
run_signer_dual retfoo > "$test_root/retent2.out" 2> "$test_root/retent2.err"
fixture_pkg retfoo retfoo 1-r3 usr/bin/retfoo three ""
stage_txn "$incoming/retent3-ready" retfoo retfoo retfoo-1-r3.apk
run_signer_dual retfoo > "$test_root/retent3.out" 2> "$test_root/retent3.err"
grep 'retention: retired 1 package' "$test_root/retent3.out" >/dev/null
live_has retfoo-1-r3.apk retfoo-1-r2.apk nofile:retfoo-1-r1.apk
test -f "$repo/retfoo-1-r1.apk"
test -f "$repo/retfoo-1-r2.apk"
test -f "$repo/retfoo-1-r3.apk"
python3 - "$hatched_repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name='retfoo'"))
assert rows == ["retfoo-1-r2", "retfoo-1-r3"], rows
PY

# Pinned dependency: an exact live pin on the oldest holds it. Fresh
# package so the pinned NVR still exists when the third lands.
fixture_pkg retpin retpin 1-r1 usr/bin/retpin one ""
stage_txn "$incoming/retpin1-ready" retpin retpin retpin-1-r1.apk
run_signer_dual retpin > "$test_root/retpin1.out" 2> "$test_root/retpin1.err"
fixture_pkg retpin retpin 1-r2 usr/bin/retpin two ""
stage_txn "$incoming/retpin2-ready" retpin retpin retpin-1-r2.apk
run_signer_dual retpin > "$test_root/retpin2.out" 2> "$test_root/retpin2.err"
fixture_pkg rethold rethold 1-r1 usr/bin/rethold hold '"retpin=1-r1"'
stage_txn "$incoming/rethold-ready" rethold rethold rethold-1-r1.apk
run_signer_dual rethold > "$test_root/rethold.out" 2> "$test_root/rethold.err"
fixture_pkg retpin retpin 1-r3 usr/bin/retpin three ""
stage_txn "$incoming/retpin3-ready" retpin retpin retpin-1-r3.apk
run_signer_dual retpin > "$test_root/retpin3.out" 2> "$test_root/retpin3.err"
grep 'retention: nothing to retire' "$test_root/retpin3.out" >/dev/null
live_has retpin-1-r1.apk retpin-1-r2.apk retpin-1-r3.apk rethold-1-r1.apk

# Split siblings retire atomically: one producer, two outputs, three
# revisions. The old pair must vanish from the live view in the same
# run - never one lingering without the other.
fixture_pkg retsplit retsplit 1-r1 usr/bin/retsplit one ""
stage_txn "$incoming/retsplit1-ready" retsplit retsplit retsplit-1-r1.apk
run_signer_dual retsplit > "$test_root/retsplit1.out" 2> "$test_root/retsplit1.err"
rm -rf "$stage/retsplitdev"
mkdir -p "$stage/retsplitdev/pkg/usr/lib/pkgconfig"
printf '%s\n' pc > "$stage/retsplitdev/pkg/usr/lib/pkgconfig/retsplit.pc"
printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"retsplitdev","origin":"retsplit","outputs":[{"dependencies":[],"description":"retsplitdev","name":"retsplitdev","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/retsplitdev/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" retsplitdev >/dev/null
mkdir "$incoming/retsplitdev1-ready"
cp "$artifacts/x86_64/retsplitdev-1-r1.apk" "$incoming/retsplitdev1-ready/"
printf '%s\n' retsplitdev > "$incoming/retsplitdev1-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/retsplitdev1-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"retsplitdev","constructors":[{"constructor":"makepkg","producer":"retsplitdev"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/retsplitdev1-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/retsplitdev1-ready" && sha256sum retsplitdev-1-r1.apk > manifest.sha256)
run_signer_dual retsplitdev > "$test_root/retsplitdev1.out" 2> "$test_root/retsplitdev1.err"
fixture_pkg retsplit retsplit 1-r2 usr/bin/retsplit two ""
rm -rf "$stage/retsplitdev"
mkdir -p "$stage/retsplitdev/pkg/usr/lib/pkgconfig"
printf '%s\n' pc > "$stage/retsplitdev/pkg/usr/lib/pkgconfig/retsplit.pc"
printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"retsplitdev","origin":"retsplit","outputs":[{"dependencies":[],"description":"retsplitdev","name":"retsplitdev","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r2"}' > "$stage/retsplitdev/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" retsplitdev >/dev/null
mkdir "$incoming/retsplit2-ready"
cp "$artifacts/x86_64/retsplit-1-r2.apk" "$artifacts/x86_64/retsplitdev-1-r2.apk" "$incoming/retsplit2-ready/"
printf '%s\n' retsplit > "$incoming/retsplit2-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/retsplit2-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"retsplit","constructors":[{"constructor":"makepkg","producer":"retsplit"},{"constructor":"makepkg","producer":"retsplitdev"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/retsplit2-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/retsplit2-ready" && sha256sum retsplit-1-r2.apk retsplitdev-1-r2.apk > manifest.sha256)
run_signer_dual retsplit > "$test_root/retsplit2.out" 2> "$test_root/retsplit2.err"
fixture_pkg retsplit retsplit 1-r3 usr/bin/retsplit three ""
rm -rf "$stage/retsplitdev"
mkdir -p "$stage/retsplitdev/pkg/usr/lib/pkgconfig"
printf '%s\n' pc > "$stage/retsplitdev/pkg/usr/lib/pkgconfig/retsplit.pc"
printf '%s\n' '{"arch":"x86_64","build_time":21,"license":"MIT","name":"retsplitdev","origin":"retsplit","outputs":[{"dependencies":[],"description":"retsplitdev","name":"retsplitdev","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r3"}' > "$stage/retsplitdev/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" retsplitdev >/dev/null
mkdir "$incoming/retsplit3-ready"
cp "$artifacts/x86_64/retsplit-1-r3.apk" "$artifacts/x86_64/retsplitdev-1-r3.apk" "$incoming/retsplit3-ready/"
printf '%s\n' retsplit > "$incoming/retsplit3-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/retsplit3-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"retsplit","constructors":[{"constructor":"makepkg","producer":"retsplit"},{"constructor":"makepkg","producer":"retsplitdev"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/retsplit3-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/retsplit3-ready" && sha256sum retsplit-1-r3.apk retsplitdev-1-r3.apk > manifest.sha256)
run_signer_dual retsplit > "$test_root/retsplit3.out" 2> "$test_root/retsplit3.err"
grep 'retention: retired 2 package' "$test_root/retsplit3.out" >/dev/null
live_has retsplit-1-r3.apk retsplit-1-r2.apk retsplitdev-1-r3.apk retsplitdev-1-r2.apk \
	nofile:retsplit-1-r1.apk nofile:retsplitdev-1-r1.apk
python3 - "$hatched_repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
for name, want in (("retsplit", ["retsplit-1-r2", "retsplit-1-r3"]),
                   ("retsplitdev", ["retsplitdev-1-r2", "retsplitdev-1-r3"])):
    rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name=?", (name,)))
    assert rows == want, (name, rows)
PY

# Explicit hold: SAPHIRA_RETAIN_NVR keeps a rank-excess NVR with no
# dependency excuse.
fixture_pkg retholdme retholdme 1-r1 usr/bin/retholdme one ""
stage_txn "$incoming/retholdme1-ready" retholdme retholdme retholdme-1-r1.apk
run_signer_dual retholdme > "$test_root/retholdme1.out" 2> "$test_root/retholdme1.err"
fixture_pkg retholdme retholdme 1-r2 usr/bin/retholdme two ""
stage_txn "$incoming/retholdme2-ready" retholdme retholdme retholdme-1-r2.apk
run_signer_dual retholdme > "$test_root/retholdme2.out" 2> "$test_root/retholdme2.err"
fixture_pkg retholdme retholdme 1-r3 usr/bin/retholdme three ""
stage_txn "$incoming/retholdme3-ready" retholdme retholdme retholdme-1-r3.apk
SAPHIRA_RETAIN_NVR="retholdme-1-r1" run_signer_dual retholdme > "$test_root/retholdme3.out" 2> "$test_root/retholdme3.err"
grep 'retention: nothing to retire' "$test_root/retholdme3.out" >/dev/null
live_has retholdme-1-r1.apk retholdme-1-r2.apk retholdme-1-r3.apk
printf '%s\n' 'hatched retention (rollback generations, pinned holds, split siblings, explicit holds): OK'

# r0 inadmissibility in the live view: hatchling keeps historical r0
# APKs forever as archive/history; hatched must not contain r0 at all.
# Published r0 claims are history, never active claims - they cannot
# block a successor, win selection, or satisfy a dependency.
run_signer_live()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatched \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}

# Hatched seeded with r0 + r1: the r0 disappears from the live view on
# the next production run, the r1 remains (files, index and rows).
fixture_pkg r0mix r0mix 1-r0 usr/bin/r0mix zero ""
stage_txn "$incoming/r0mix0-ready" r0mix r0mix r0mix-1-r0.apk
run_signer_live r0mix > "$test_root/r0mix0.out" 2> "$test_root/r0mix0.err"
fixture_pkg r0mix r0mix 1-r1 usr/bin/r0mix one ""
stage_txn "$incoming/r0mix1-ready" r0mix r0mix r0mix-1-r1.apk
run_signer_live r0mix > "$test_root/r0mix1.out" 2> "$test_root/r0mix1.err"
live_has r0mix-1-r0.apk r0mix-1-r1.apk
fixture_pkg r0trig r0trig 1-r1 usr/bin/r0trig trig ""
stage_txn "$incoming/r0trig-ready" r0trig r0trig r0trig-1-r1.apk
run_signer_dual r0trig > "$test_root/r0trig.out" 2> "$test_root/r0trig.err"
grep 'r0mix-1-r0.apk' "$test_root/r0trig.out" >/dev/null
live_has r0mix-1-r1.apk r0trig-1-r1.apk nofile:r0mix-1-r0.apk
python3 - "$hatched_repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name='r0mix'"))
assert rows == ["r0mix-1-r1"], rows
PY

# Hatched seeded with r0 only: the r0 disappears and the package is
# absent rather than retained.
fixture_pkg r0lone r0lone 1-r0 usr/bin/r0lone zero ""
stage_txn "$incoming/r0lone-ready" r0lone r0lone r0lone-1-r0.apk
run_signer_live r0lone > "$test_root/r0lone.out" 2> "$test_root/r0lone.err"
live_has r0lone-1-r0.apk
fixture_pkg r0trigb r0trigb 1-r1 usr/bin/r0trigb trig ""
stage_txn "$incoming/r0trigb-ready" r0trigb r0trigb r0trigb-1-r1.apk
run_signer_dual r0trigb > "$test_root/r0lone-trig.out" 2> "$test_root/r0lone-trig.err"
live_has nofile:r0lone-1-r0.apk
python3 - "$hatched_repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = list(conn.execute("SELECT nvr FROM packages WHERE name='r0lone'"))
assert rows == [], rows
PY

# Exact dependency on an r0: publication fails closed and identifies the
# broken dependent. The r0 is NOT preserved to satisfy it. Afterwards
# the consumer is fixed at r1+ (r0need-1-r1, r0cons-1-r2 on the exact r1
# pin), which unbreaks the live view and retires the r0 - otherwise the
# broken pair would poison every later production run.
fixture_pkg r0cons r0cons 1-r1 usr/bin/r0cons cons '"r0need=1-r0"'
stage_txn "$incoming/r0cons-ready" r0cons r0cons r0cons-1-r1.apk
run_signer_live r0cons > "$test_root/r0cons.out" 2> "$test_root/r0cons.err"
fixture_pkg r0need r0need 1-r0 usr/bin/r0need zero ""
stage_txn "$incoming/r0need-ready" r0need r0need r0need-1-r0.apk
run_signer_live r0need > "$test_root/r0need.out" 2> "$test_root/r0need.err"
live_before=$(find "$hatched_repo" -type f -printf '%P\n' | sort | sha256sum)
fixture_pkg r0trigc r0trigc 1-r1 usr/bin/r0trigc trig ""
stage_txn "$incoming/r0trigc-ready" r0trigc r0trigc r0trigc-1-r1.apk
if run_signer_dual r0trigc > "$test_root/r0dep.out" 2> "$test_root/r0dep.err"; then
	printf '%s\n' 'live dependency on r0 unexpectedly published' >&2
	exit 1
fi
grep 'retention refused' "$test_root/r0dep.err" >/dev/null
grep 'broken live dependency' "$test_root/r0dep.err" >/dev/null
grep 'r0cons-1-r1' "$test_root/r0dep.err" >/dev/null
grep "depends on 'r0need=1-r0'" "$test_root/r0dep.err" >/dev/null
[ "$live_before" = "$(find "$hatched_repo" -type f -printf '%P\n' | sort | sha256sum)" ]
live_has r0need-1-r0.apk r0cons-1-r1.apk
rm -rf "$incoming/r0trigc-ready"
fixture_pkg r0need r0need 1-r1 usr/bin/r0need zero ""
stage_txn "$incoming/r0needfix-ready" r0need r0need r0need-1-r1.apk
fixture_pkg r0cons r0cons 1-r2 usr/bin/r0cons cons '"r0need=1-r1"'
stage_txn "$incoming/r0consfix-ready" r0cons r0cons r0cons-1-r2.apk
run_signer_dual r0need r0cons > "$test_root/r0depfix.out" 2> "$test_root/r0depfix.err"
grep 'r0need-1-r0.apk' "$test_root/r0depfix.out" >/dev/null
live_has r0need-1-r1.apk r0cons-1-r1.apk r0cons-1-r2.apk nofile:r0need-1-r0.apk

# Explicit SAPHIRA_RETAIN_NVR naming an r0: rejected loudly. The r0 is
# then superseded by a same-name r1 so later runs stay clean.
fixture_pkg r0held r0held 1-r0 usr/bin/r0held zero ""
stage_txn "$incoming/r0held-ready" r0held r0held r0held-1-r0.apk
run_signer_live r0held > "$test_root/r0held.out" 2> "$test_root/r0held.err"
fixture_pkg r0trigd r0trigd 1-r1 usr/bin/r0trigd trig ""
stage_txn "$incoming/r0trigd-ready" r0trigd r0trigd r0trigd-1-r1.apk
if SAPHIRA_RETAIN_NVR="r0held-1-r0" run_signer_dual r0trigd > "$test_root/r0hold.out" 2> "$test_root/r0hold.err"; then
	printf '%s\n' 'explicit hold on r0 unexpectedly published' >&2
	exit 1
fi
grep 'retention refused' "$test_root/r0hold.err" >/dev/null
grep 'explicit retention hold on r0 is rejected' "$test_root/r0hold.err" >/dev/null
grep 'r0held-1-r0' "$test_root/r0hold.err" >/dev/null
rm -rf "$incoming/r0trigd-ready"
fixture_pkg r0held r0held 1-r1 usr/bin/r0held zero ""
stage_txn "$incoming/r0heldfix-ready" r0held r0held r0held-1-r1.apk
run_signer_live r0held > "$test_root/r0heldfix.out" 2> "$test_root/r0heldfix.err"

# Hatchling containing a historical r0: the archive retains the APK and
# its rows, and the r0 does not block the r1/r2 successor ownership.
fixture_pkg r0arc r0arc 1-r0 usr/bin/r0arc zero ""
stage_txn "$incoming/r0arc0-ready" r0arc r0arc r0arc-1-r0.apk
run_signer r0arc > "$test_root/r0arc0.out" 2> "$test_root/r0arc0.err"
fixture_pkg r0arc r0arc 1-r1 usr/bin/r0arc one ""
stage_txn "$incoming/r0arc1-ready" r0arc r0arc r0arc-1-r1.apk
run_signer_dual r0arc > "$test_root/r0arc1.out" 2> "$test_root/r0arc1.err"
fixture_pkg r0arc r0arc 1-r2 usr/bin/r0arc two ""
stage_txn "$incoming/r0arc2-ready" r0arc r0arc r0arc-1-r2.apk
run_signer_dual r0arc > "$test_root/r0arc2.out" 2> "$test_root/r0arc2.err"
test -f "$repo/r0arc-1-r0.apk"
test -f "$repo/r0arc-1-r1.apk"
test -f "$repo/r0arc-1-r2.apk"
live_has r0arc-1-r1.apk r0arc-1-r2.apk nofile:r0arc-1-r0.apk
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name='r0arc'"))
assert rows == ["r0arc-1-r0", "r0arc-1-r1", "r0arc-1-r2"], rows
PY

# The emscripten case: ems-6.0.5-r0 historically owned the .pc files and
# was never rebuilt as a base r1; ems-dev-6.0.5-r1 now correctly owns
# them. The historical r0 claim must not collide with the successor.
# Hatchling keeps the r0 APK; hatched contains no r0.
mkdir -p "$stage/ems/pkg/usr/lib/pkgconfig"
printf '%s\n' pc > "$stage/ems/pkg/usr/lib/pkgconfig/ems.pc"
printf '%s\n' '{"arch":"x86_64","build_time":22,"license":"MIT","name":"ems","origin":"ems","outputs":[{"dependencies":[],"description":"ems","name":"ems","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"6.0.5-r0"}' > "$stage/ems/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" ems >/dev/null
mkdir "$incoming/ems0-ready"
cp "$artifacts/x86_64/ems-6.0.5-r0.apk" "$incoming/ems0-ready/"
printf '%s\n' ems > "$incoming/ems0-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/ems0-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"ems","constructors":[{"constructor":"makepkg","producer":"ems"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/ems0-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/ems0-ready" && sha256sum ems-6.0.5-r0.apk > manifest.sha256)
run_signer ems > "$test_root/ems0.out" 2> "$test_root/ems0.err"
mkdir -p "$stage/emsdev/pkg/usr/lib/pkgconfig"
printf '%s\n' pc > "$stage/emsdev/pkg/usr/lib/pkgconfig/ems.pc"
printf '%s\n' '{"arch":"x86_64","build_time":22,"license":"MIT","name":"emsdev","origin":"ems","outputs":[{"dependencies":[],"description":"ems-dev","name":"ems-dev","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"6.0.5-r1"}' > "$stage/emsdev/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" emsdev >/dev/null
mkdir "$incoming/emsdev1-ready"
cp "$artifacts/x86_64/ems-dev-6.0.5-r1.apk" "$incoming/emsdev1-ready/"
printf '%s\n' emsdev > "$incoming/emsdev1-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/emsdev1-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"emsdev","constructors":[{"constructor":"makepkg","producer":"emsdev"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/emsdev1-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/emsdev1-ready" && sha256sum ems-dev-6.0.5-r1.apk > manifest.sha256)
run_signer_dual emsdev > "$test_root/emsdev1.out" 2> "$test_root/emsdev1.err"
test -f "$repo/ems-6.0.5-r0.apk"
apk adbdump "$repo/Packages.adb" | grep -q '6\.0\.5-r0'
live_has ems-dev-6.0.5-r1.apk nofile:ems-6.0.5-r0.apk
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name='ems'"))
assert rows == ["ems-6.0.5-r0"], rows
PY
python3 - "$hatched_repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = list(conn.execute("SELECT nvr FROM packages WHERE name='ems'"))
assert rows == [], rows
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name='ems-dev'"))
assert rows == ["ems-dev-6.0.5-r1"], rows
PY

# Shared init selector: systemd + openrc co-own sbin/init (PID 1's
# canonical path cannot move to /usr/sbin like the split halt/
# poweroff/reboot/shutdown siblings). A third claimant still fails.
mkdir -p "$stage/systemd/pkg/sbin" "$stage/openrc/pkg/sbin"
ln -s ../lib/systemd/systemd "$stage/systemd/pkg/sbin/init"
ln -s openrc-init "$stage/openrc/pkg/sbin/init"
printf '%s\n' '{"arch":"x86_64","build_time":30,"license":"MIT","name":"systemd","origin":"systemd","outputs":[{"dependencies":[],"description":"systemd","name":"systemd","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/systemd/manifest.json"
printf '%s\n' '{"arch":"x86_64","build_time":30,"license":"MIT","name":"openrc","origin":"openrc","outputs":[{"dependencies":[],"description":"openrc","name":"openrc","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/openrc/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" systemd >/dev/null
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" openrc >/dev/null
mkdir "$incoming/initselect-ready"
cp "$artifacts/x86_64/systemd-1-r1.apk" "$artifacts/x86_64/openrc-1-r1.apk" "$incoming/initselect-ready/"
printf '%s\n' systemd > "$incoming/initselect-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/initselect-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"systemd","constructors":[{"constructor":"makepkg","producer":"systemd"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/initselect-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/initselect-ready" && sha256sum systemd-1-r1.apk openrc-1-r1.apk > manifest.sha256)
run_signer_dual systemd > "$test_root/initselect.out" 2> "$test_root/initselect.err"
grep 'shared init selector' "$test_root/initselect.out" >/dev/null
grep 'sbin/init' "$test_root/initselect.out" >/dev/null
test -f "$repo/systemd-1-r1.apk"
test -f "$repo/openrc-1-r1.apk"
test -f "$hatched_repo/systemd-1-r1.apk"
test -f "$hatched_repo/openrc-1-r1.apk"
mkdir -p "$stage/impostor/pkg/sbin"
ln -s /bin/true "$stage/impostor/pkg/sbin/init"
printf '%s\n' '{"arch":"x86_64","build_time":31,"license":"MIT","name":"impostor","origin":"impostor","outputs":[{"dependencies":[],"description":"impostor","name":"impostor","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' > "$stage/impostor/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" impostor >/dev/null
mkdir "$incoming/impostor-ready"
cp "$artifacts/x86_64/impostor-1-r1.apk" "$incoming/impostor-ready/"
printf '%s\n' impostor > "$incoming/impostor-ready/target"
printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$incoming/impostor-ready/package-seed.json"
printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"impostor","constructors":[{"constructor":"makepkg","producer":"impostor"}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$incoming/impostor-ready/artifact-manifest.json"
(CDPATH= cd -- "$incoming/impostor-ready" && sha256sum impostor-1-r1.apk > manifest.sha256)
if run_signer_dual impostor > "$test_root/impostor.out" 2> "$test_root/impostor.err"; then
	printf '%s\n' 'third init claimant unexpectedly published' >&2
	exit 1
fi
grep 'file ownership collision' "$test_root/impostor.err" >/dev/null
grep 'sbin/init' "$test_root/impostor.err" >/dev/null
test ! -e "$repo/impostor-1-r1.apk"
test ! -e "$hatched_repo/impostor-1-r1.apk"
rm -rf "$incoming/impostor-ready"
printf '%s\n' 'shared init selector (systemd+openrc co-own sbin/init, third claimant refused): OK'
# The full audit resolves declaration-extraction providers, so the bare
# helper deps of the earlier account fixtures (bash, coreutils,
# saphira-baselayout - auto-added by makepkg) need published stubs
# first, exactly like repo-state.sh seeds its own.
fixture_pkg stubbash bash 1-r1 usr/bin/bash bash ""
stage_txn "$incoming/stubbash-ready" bash stubbash bash-1-r1.apk
fixture_pkg stubcore coreutils 1-r1 usr/bin/coreutils core ""
stage_txn "$incoming/stubcore-ready" coreutils stubcore coreutils-1-r1.apk
fixture_pkg stubbase saphira-baselayout 1-r1 usr/bin/base base ""
stage_txn "$incoming/stubbase-ready" saphira-baselayout stubbase saphira-baselayout-1-r1.apk
run_signer_dual bash coreutils saphira-baselayout > "$test_root/stubs.out" 2> "$test_root/stubs.err"
fixture_pkg r0heal r0heal 1-r1 usr/bin/r0heal heal ""
stage_txn "$incoming/r0heal-ready" r0heal r0heal r0heal-1-r1.apk
run_signer_dual --full-audit r0heal > "$test_root/emsheal.out" 2> "$test_root/emsheal.err"
grep 'full audit' "$test_root/emsheal.out" >/dev/null
test -f "$repo/ems-6.0.5-r0.apk"
live_has ems-dev-6.0.5-r1.apk r0heal-1-r1.apk nofile:ems-6.0.5-r0.apk
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name='ems'"))
assert rows == ["ems-6.0.5-r0"], rows
PY
printf '%s\n' 'r0 inadmissibility (live purge, broken-dep refusal, hold rejection, archive history, emscripten split, heal): OK'

# Heal mode: --full-audit with an empty stage reconciles indexes and
# repository.db with disk truth after sanctioned out-of-band removal
# of superseded artifacts, and publishes nothing. An empty stage
# without --full-audit stays a refusal.
fixture_pkg healkeep healkeep 1-r1 usr/bin/healkeep keep ""
stage_txn "$incoming/healkeep-ready" healkeep healkeep healkeep-1-r1.apk
fixture_pkg healdrop healdrop 1-r1 usr/bin/healdrop drop ""
stage_txn "$incoming/healdrop-ready" healdrop healdrop healdrop-1-r1.apk
run_signer healkeep healdrop >/dev/null
test -f "$repo/healkeep-1-r1.apk"
test -f "$repo/healdrop-1-r1.apk"
# Heal needs a clean stage: stale refused *-ready residue elsewhere in
# the shared incoming dir must keep taking the normal publish path
# (loud refusal), never a silent heal. Scope the empty stage to a
# fresh dir; the repo under repair stays shared by design.
heal_stage=$test_root/heal-stage
mkdir -p "$heal_stage"
run_heal()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$heal_stage \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}
if run_heal > "$test_root/healempty.out" 2> "$test_root/healempty.err"; then
	printf '%s\n' 'empty stage unexpectedly published' >&2
	exit 1
fi
grep 'no complete ready transactions' "$test_root/healempty.err" >/dev/null
find "$incoming" -mindepth 1 -maxdepth 1 | sort > "$test_root/heal-incoming-before.txt"
rm "$repo/healdrop-1-r1.apk"
run_heal --full-audit > "$test_root/heal.out" 2> "$test_root/heal.err"
grep 'heals repository indexes from disk state' "$test_root/heal.out" >/dev/null
test -f "$repo/healkeep-1-r1.apk"
test ! -e "$repo/healdrop-1-r1.apk"
[ "$(apk adbdump "$repo/Packages.adb" | awk '/^  - name: healkeep$/ { count++ } END { print count + 0 }')" -eq 1 ]
if apk adbdump "$repo/Packages.adb" | grep -q healdrop; then
	printf '%s\n' 'removed package still indexed after heal' >&2
	exit 1
fi
find "$incoming" -mindepth 1 -maxdepth 1 | sort > "$test_root/heal-incoming-after.txt"
cmp "$test_root/heal-incoming-before.txt" "$test_root/heal-incoming-after.txt" >/dev/null
# Heal stages nothing: no transaction dirs at any depth (the signer
# may create an empty arch subdir as setup; contents are what matter).
test -z "$(find "$heal_stage" -mindepth 2 -print -quit)"
python3 - "$repo/repository.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
rows = sorted(r[0] for r in conn.execute("SELECT nvr FROM packages WHERE name IN ('healkeep', 'healdrop')"))
assert rows == ["healkeep-1-r1"], rows
PY
printf '%s\n' 'heal mode (empty-stage refusal, out-of-band removal reconciliation, no publish): OK'

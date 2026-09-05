#!/bin/sh

set -eu

[ "$#" -eq 3 ] || {
	printf 'usage: %s SEED-REPO SIGN-APK-REPO MAKEPKG\n' "$0" >&2
	exit 1
}

seed_repo=$1
sign_repo=$2
makepkg=$3
source_root=$(CDPATH= cd -- "$(dirname -- "$seed_repo")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-seed-repo-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
incoming=$test_root/incoming/x86_64
stage=$test_root/stage
artifacts=$test_root/artifacts
keys=$test_root/keys
mkdir -p "$test_root/repository/hatchling/x86_64" "$incoming" "$artifacts" "$keys" "$test_root/package-tmp"

openssl genrsa -traditional -out "$test_root/test-repository.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$test_root/test-repository.rsa" -pubout -out "$keys/test-repository.rsa.pub" >/dev/null 2>&1

build_and_stage()
{
	package=$1
	version=$2
	producer=$package-$version
	mkdir -p "$stage/$producer/pkg/usr/bin"
	printf '%s\n' "$package" > "$stage/$producer/pkg/usr/bin/$package"
	printf '%s' "{\"arch\":\"x86_64\",\"build_time\":1,\"license\":\"MIT\",\"name\":\"$producer\",\"origin\":\"$package\",\"outputs\":[{\"dependencies\":[],\"description\":\"$package\",\"name\":\"$package\",\"payload\":\"pkg\"}],\"schema\":\"saphira-stage-manifest/v1\",\"url\":\"https://example.invalid/\",\"version\":\"$version\"}" \
		> "$stage/$producer/manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$producer" >/dev/null
	ready=$incoming/$producer-ready
	mkdir "$ready"
	cp "$artifacts/x86_64/$package-$version.apk" "$ready/"
	printf '%s\n' "$producer" > "$ready/target"
	printf '%s\n' '{"schema":"saphira-bootstrap-seed/v1","generation":"test","manifest":"test","manifest_sha256":"test","entries":[]}' > "$ready/bootstrap-seed.json"
	printf '%s\n' "{\"schema\":\"saphira-build-artifacts/v1\",\"target\":\"$producer\",\"constructors\":[{\"constructor\":\"makepkg\",\"producer\":\"$producer\"}],\"bootstrap_seed\":{\"schema\":\"saphira-bootstrap-seed/v1\",\"generation\":\"test\",\"manifest\":\"test\",\"manifest_sha256\":\"test\",\"entries\":[]}}" > "$ready/artifact-manifest.json"
	(CDPATH= cd -- "$ready" && sha256sum "$package-$version.apk" > manifest.sha256)
}

run_signer()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES=hatchling \
		unshare --map-root-user "$sign_repo"
}

run_seeder()
{
	exclude=$1
	shift
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository SAPHIRA_PACKAGE_TMP=$test_root/package-tmp \
	SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub \
	SAPHIRA_REPO_NAMES=hatchling SAPHIRA_GENESIS_EXCLUDE=$exclude \
	SAPHIRA_VERSION_LINES_FILE=${SAPHIRA_TEST_VERSION_LINES:-$test_root/empty-lines.conf} \
		unshare --map-root-user "$seed_repo" "$@"
}

: > "$test_root/empty-lines.conf"

# Two packages, two published revisions each: hatchling holds the full
# r0+r1 history; a genesis seed must take only the latest of each name.
build_and_stage make 9-r0
build_and_stage make 9-r1
build_and_stage bash 5.3-r0
build_and_stage bash 5.3-r1
run_signer >/dev/null
[ "$(apk adbdump "$test_root/repository/hatchling/x86_64/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 4 ]

run_seeder bash hatched >/dev/null
hatched=$test_root/repository/hatched/x86_64
test -f "$hatched/make-9-r1.apk"
test -f "$hatched/Packages.adb"
test -f "$hatched/APKINDEX.tar.gz"
test -f "$hatched/genesis.json"
test ! -e "$hatched/make-9-r0.apk"
test ! -e "$hatched/bash-5.3-r1.apk"
apk verify --keys-dir "$keys" "$hatched/make-9-r1.apk"
apk verify --keys-dir "$keys" "$hatched/Packages.adb"
apk verify --keys-dir "$keys" "$hatched/APKINDEX.tar.gz"
[ "$(apk adbdump "$hatched/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 1 ]
[ -z "$(find "$hatched" -type l -print -quit)" ]
[ -z "$(find "$hatched" -type f ! -links 1 -print -quit)" ]
python3 - "$hatched/genesis.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    receipt = json.load(stream)
assert receipt["schema"] == "saphira-repo-genesis/v1"
assert receipt["source"] == "hatchling"
assert receipt["repository"] == "hatched"
assert receipt["package_count"] == 1
assert receipt["excluded"] == ["bash"]
PY

# Re-seeding an existing generation is refused, as is seeding a name that
# is already listed.
if run_seeder bash hatched > "$test_root/reseed.out" 2> "$test_root/reseed.err"; then
	printf '%s\n' 're-seeding an existing generation unexpectedly succeeded' >&2
	exit 1
fi
grep 'already exists' "$test_root/reseed.err" >/dev/null
if run_seeder '' hatchling > "$test_root/listed.out" 2> "$test_root/listed.err"; then
	printf '%s\n' 'seeding a listed generation unexpectedly succeeded' >&2
	exit 1
fi
grep 'already listed' "$test_root/listed.err" >/dev/null

# Without exclusions every latest revision crosses the boundary.
run_seeder '' fledged >/dev/null
fledged=$test_root/repository/fledged/x86_64
test -f "$fledged/make-9-r1.apk"
test -f "$fledged/bash-5.3-r1.apk"
test ! -e "$fledged/make-9-r0.apk"
test ! -e "$fledged/bash-5.3-r0.apk"
apk verify --keys-dir "$keys" "$fledged/Packages.adb"
apk verify --keys-dir "$keys" "$fledged/APKINDEX.tar.gz"

# --- parallel version lines -------------------------------------------------
# kernel deliberately maintains two live pkgver lines. Without policy the
# seed collapses to latest-per-name (7.2.2 only); with the generic
# version-lines policy every declared line keeps its highest revision.
build_and_stage kernel 7.1.5-r1
build_and_stage kernel 7.2.2-r1
build_and_stage kernel 7.2.2-r3
run_signer >/dev/null

run_seeder '' lineless >/dev/null
lineless=$test_root/repository/lineless/x86_64
test -f "$lineless/kernel-7.2.2-r3.apk"
test ! -e "$lineless/kernel-7.2.2-r1.apk"
test ! -e "$lineless/kernel-7.1.5-r1.apk"

printf '%s\n' '# policy fixture' 'kernel 7.1.5 7.2.2' > "$test_root/kernel-lines.conf"
SAPHIRA_TEST_VERSION_LINES=$test_root/kernel-lines.conf run_seeder '' lined >/dev/null
lined=$test_root/repository/lined/x86_64
test -f "$lined/kernel-7.1.5-r1.apk"
test -f "$lined/kernel-7.2.2-r3.apk"
test ! -e "$lined/kernel-7.2.2-r1.apk"
test -f "$lined/make-9-r1.apk"
apk verify --keys-dir "$keys" "$lined/kernel-7.1.5-r1.apk"
apk verify --keys-dir "$keys" "$lined/Packages.adb"
apk verify --keys-dir "$keys" "$lined/APKINDEX.tar.gz"
python3 - "$lined/genesis.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    receipt = json.load(stream)
assert receipt["version_lines"] == {"kernel": ["7.1.5", "7.2.2"]}, receipt
assert receipt["package_count"] == 4, receipt  # make-9-r1, bash-5.3-r1, kernel 7.1.5-r1, kernel 7.2.2-r3
PY

# A declared line with no source package warns and is skipped.
printf '%s\n' 'kernel 7.1.5 7.2.2 8.0' > "$test_root/kernel-lines-gap.conf"
if ! SAPHIRA_TEST_VERSION_LINES=$test_root/kernel-lines-gap.conf \
		run_seeder '' gapped > "$test_root/gapped.out" 2> "$test_root/gapped.err"; then
	printf '%s\n' 'version-lines gap unexpectedly aborted the seed' >&2
	exit 1
fi
grep 'declared version line kernel 8.0 has no package' "$test_root/gapped.err" >/dev/null
gapped=$test_root/repository/gapped/x86_64
test -f "$gapped/kernel-7.1.5-r1.apk"
test -f "$gapped/kernel-7.2.2-r3.apk"

# A version-lines name absent from the source repository entirely warns too.
printf '%s\n' 'ghostpkg 1.0' > "$test_root/ghost-lines.conf"
SAPHIRA_TEST_VERSION_LINES=$test_root/ghost-lines.conf \
	run_seeder '' ghostlined > "$test_root/ghostlined.out" 2> "$test_root/ghostlined.err"
grep 'version-lines name ghostpkg is absent' "$test_root/ghostlined.err" >/dev/null

# An explicitly configured policy file that does not exist is an error.
if SAPHIRA_TEST_VERSION_LINES=$test_root/absent-lines.conf run_seeder '' nofile \
		> "$test_root/nofile.out" 2> "$test_root/nofile.err"; then
	printf '%s\n' 'missing explicit version-lines file unexpectedly succeeded' >&2
	exit 1
fi
grep 'SAPHIRA_VERSION_LINES_FILE does not exist' "$test_root/nofile.err" >/dev/null

printf '%s\n' 'genesis seeding: latest-per-name real copies, exclusions, receipts, parallel version lines, and refusal tests: OK'

# Ownership normalization (unit level): with SUDO_UID set the seeded
# generation and its contents are chowned to the invoking user with the
# configured repository group, and directories gain the setgid bit.
unshare --map-root-user python3 - "$seed_repo" "$test_root" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import stat
import sys

spec = importlib.util.spec_from_loader(
    "seed_repo_under_test",
    importlib.machinery.SourceFileLoader("seed_repo_under_test", sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

root = pathlib.Path(sys.argv[2]) / "ownership"
target = root / "seeded"
target.mkdir(parents=True)
(target / "pkg-1.0-r0.apk").write_text("apk")
os.environ["SUDO_UID"] = "0"
os.environ["SAPHIRA_REPO_GROUP"] = "root"
module.normalize_ownership(target)
module.normalize_ownership(target / "pkg-1.0-r0.apk")
info = target.stat()
assert info.st_uid == 0 and info.st_gid == 0, (info.st_uid, info.st_gid)
assert info.st_mode & stat.S_ISGID, oct(info.st_mode)
file_info = (target / "pkg-1.0-r0.apk").stat()
assert file_info.st_uid == 0 and file_info.st_gid == 0
# Without SUDO_UID the function is a no-op.
del os.environ["SUDO_UID"]
module.normalize_ownership(target / "pkg-1.0-r0.apk")
print("ownership normalization tests: OK")
PY

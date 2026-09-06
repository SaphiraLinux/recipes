#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s BUILDPKG\n' "$0" >&2
	exit 1
}

buildpkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$buildpkg")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-clean-build-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
recipes=$test_root/recipes
build_root=$test_root/build
incoming=$test_root/incoming
mkdir -p "$recipes" "$build_root" "$incoming"

run_buildpkg()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_RECIPE_ROOT=$recipes \
	SAPHIRA_REFERENCE_RECIPE_ROOT=$test_root/reference \
	SAPHIRA_CPORTS_ROOT=$test_root/cports \
	SAPHIRA_BUILD_ROOT=$build_root \
	SAPHIRA_REPO_DIR=${SAPHIRA_TEST_REPO_DIR:-/out/stage4/packages} \
	SAPHIRA_INCOMING_DIR=$incoming \
	SAPHIRA_BINDIR=$source_root/saphira-packager/files \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp \
	SAPHIRA_BOOTSTRAP_ROOT=/ \
	SAPHIRA_BOOTSTRAP_MANIFEST=$source_root/saphira-packager/files/bootstrap-v0.1.paths \
	SAPHIRA_HOST_RESOLV_CONF=/etc/resolv.conf SAPHIRA_HOST_HOSTS_FILE=/etc/hosts \
	SAPHIRA_BUILD_SEED='saphira-base-abi apk-tools bash libcap coreutils findutils pcre2 grep python3 ca-certificates curl tar' \
	SAPHIRA_SOURCE_CACHE=${SAPHIRA_TEST_SOURCE_CACHE:-$test_root/source-cache} \
		"$buildpkg" "$@"
}

recipe_header()
{
	package=$1
	depends=$2
	subpackages=${3-}
	version=${4:-1}
	mkdir -p "$recipes/$package"
	printf '%s\n' \
		'#!/bin/bash' \
		"pkgname=$package" \
		"pkgver=$version" \
		'pkgrel=1' \
		'pkgarch=x86_64' \
		"pkgdesc='$package integration fixture'" \
		'license=MIT' \
		"origin=$package" \
		'repo=test' \
		'url=https://example.invalid/' \
		'depends=""' \
		"makedepends='$depends'" \
		"subpackages='$subpackages'" > "$recipes/$package/recipe.sh"
}

recipe_header make '' 'make-doc make-libs' 9
printf '%s\n' \
	'recipe_build() { :; }' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin" "$DESTDIR/usr/share/doc/make" "$DESTDIR/usr/lib"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/make"' \
	'	chmod 755 "$DESTDIR/usr/bin/make"' \
	'	printf "%s\n" documentation > "$DESTDIR/usr/share/doc/make/README"' \
	'	printf "fake-elf" > "$DESTDIR/usr/lib/libmake.so.9.0.0"' \
	'}' >> "$recipes/make/recipe.sh"

recipe_header fakeroot 'acl-dev make>=9-r1' '' 9
printf '%s\n' \
	'recipe_build() {' \
	'	command -v make >/dev/null' \
	'	test ! -e /usr/share/doc/make/README' \
	'	test ! -e /usr/include/FlexLexer.h' \
	'	test ! -e /usr/lib/libLLVM.so.22.1' \
	'	test ! -e /usr/lib/pkgconfig/libkmod.pc' \
	'	test -s /etc/resolv.conf' \
	'	test -s /etc/hosts' \
	'	test -s /etc/ssl/certs/ca-certificates.crt' \
	'    test "$(readlink /bin/sh)" = bash' \
	'    test -e /usr/bin/env' \
	'	test ! -e /lib64' \
	'	test ! -e /usr/lib64' \
	'	! command -v sudo >/dev/null 2>&1' \
	'	python3 -c '\''import importlib.util; assert importlib.util.find_spec("advanced_context") is None'\''' \
	'	python3 -c '\''assert any(" - overlay " in line and line.split()[4] == "/" for line in open("/proc/self/mountinfo"))'\''' \
	'}' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/fakeroot"' \
	'	chmod 755 "$DESTDIR/usr/bin/fakeroot"' \
	'}' >> "$recipes/fakeroot/recipe.sh"

host_before=$(sha256sum /lib/apk/db/installed /etc/apk/world)
# The live generation repository: last name in SAPHIRA_REPO_NAMES.
test_repo_base=${SAPHIRA_TEST_REPO_DIR:-/out/stage4/packages}
repo_names=${SAPHIRA_TEST_REPO_NAMES:-hatchling}
live_repo=$test_repo_base/${repo_names##* }/x86_64
if [ ! -d "$live_repo" ]; then
	printf '%s\n' "clean-build: live generation repository is missing: $live_repo (genesis move pending?)" >&2
	exit 1
fi
repo_before=$(find "$live_repo" -maxdepth 1 -type f -printf '%f %s %T@\n' | sort | sha256sum)
if ! run_buildpkg fakeroot; then
	sed -n '1,320p' "$build_root/fakeroot.buildpkg/logs/buildpkg.log" >&2
	exit 1
fi
host_after=$(sha256sum /lib/apk/db/installed /etc/apk/world)
repo_after=$(find "$live_repo" -maxdepth 1 -type f -printf '%f %s %T@\n' | sort | sha256sum)
[ "$host_before" = "$host_after" ]
[ "$repo_before" = "$repo_after" ]

test ! -e "$build_root/fakeroot.buildpkg"

# Canonical OverlayFS base root: one physical root backing every workspace,
# with a visible state manifest and no leftover staging/retired directories.
test -d "$build_root/rootfs_overlay/base"
test -f "$build_root/rootfs_overlay/state/base.json"
test -f "$build_root/rootfs_overlay/state/bootstrap-seed.json"
test "$(readlink "$build_root/rootfs_overlay/base/bin/sh")" = bash
test -e "$build_root/rootfs_overlay/base/usr/bin/apk"
test -s "$build_root/rootfs_overlay/base/etc/ssl/certs/ca-certificates.crt"
[ -z "$(find "$build_root/rootfs_overlay" -maxdepth 1 \( -name 'base.new' -o -name 'base.old-*' \) -print -quit)" ]
base_inode=$(stat -c %i "$build_root/rootfs_overlay/base")
set -- "$incoming/x86_64"/fakeroot-*-ready
[ "$#" -eq 1 ] && [ -d "$1" ]
ready=$1
test -f "$ready/make-9-r1.apk"
test -f "$ready/make-doc-9-r1.apk"
test -f "$ready/make-libs-9-r1.apk"
test -f "$ready/fakeroot-9-r1.apk"
apk verify --allow-untrusted "$ready/make-9-r1.apk"
apk verify --allow-untrusted "$ready/make-doc-9-r1.apk"
apk verify --allow-untrusted "$ready/make-libs-9-r1.apk"
apk verify --allow-untrusted "$ready/fakeroot-9-r1.apk"
python3 - "$ready/artifact-manifest.json" "$ready/bootstrap-seed.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)
assert manifest["schema"] == "saphira-build-artifacts/v1"
assert manifest["target"] == "fakeroot"
assert [item["producer"] for item in manifest["constructors"]] == ["make", "fakeroot"]
assert all(item["constructor"] == "makepkg" for item in manifest["constructors"])
seed = manifest["bootstrap_seed"]
assert seed["schema"] == "saphira-bootstrap-seed/v1"
paths = {item["path"] for item in seed["entries"]}
assert "/lib/ld-musl-x86_64.so.1" in paths
assert "/usr/include/stdio.h" in paths
assert "/usr/include/FlexLexer.h" not in paths
assert not any(path.startswith(("/lib64", "/usr/lib64")) for path in paths)
with open(sys.argv[2], encoding="utf-8") as stream:
    assert json.load(stream) == seed
PY
(CDPATH= cd -- "$ready" && sha256sum -c manifest.sha256 >/dev/null)

# Failed state is retained; marked retry is replaceable.
recipe_header integration-failure ''
printf '%s\n' 'recipe_build() { return 1; }' 'recipe_install() { :; }' >> "$recipes/integration-failure/recipe.sh"
if run_buildpkg integration-failure > "$test_root/failure-1.out" 2> "$test_root/failure-1.err"; then
	printf '%s\n' 'failed build unexpectedly succeeded' >&2
	exit 1
fi
failed=$build_root/integration-failure.buildpkg
test -f "$failed/FAILED"
grep 'saphira-buildpkg-failed/v1' "$failed/FAILED" >/dev/null
test -f "$failed/plan.json"

# Failed workspaces retain the overlay upper, workdir, empty merged-root
# mountpoint, holder record and recovery instructions; the merged root is
# still mounted in the holder's namespace for diagnosis.
test -d "$failed/upper"
test -d "$failed/work"
test -d "$failed/root"
test -z "$(ls -A "$failed/root")"
test -f "$failed/overlay-holder.json"
test -f "$failed/OVERLAY-RECOVER.txt"
holder_pid=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$failed/overlay-holder.json")
grep -q ' - overlay ' "/proc/$holder_pid/mountinfo"

printf '%s\n' old > "$failed/retry-sentinel"
if run_buildpkg integration-failure > "$test_root/failure-2.out" 2> "$test_root/failure-2.err"; then
	printf '%s\n' 'retrying failed build unexpectedly succeeded' >&2
	exit 1
fi
test -f "$failed/FAILED"
test ! -e "$failed/retry-sentinel"

# A retry replaces the old holder (exactly one live holder per workspace)
# and still reuses the same immutable base root (no second physical root).
holder_pid_2=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$failed/overlay-holder.json")
[ "$holder_pid_2" != "$holder_pid" ]
grep -q ' - overlay ' "/proc/$holder_pid_2/mountinfo"
[ "$(stat -c %i "$build_root/rootfs_overlay/base")" = "$base_inode" ]

# Unmarked workspaces are never removed as a retry convenience.
mkdir "$build_root/collision.buildpkg"
printf '%s\n' keep > "$build_root/collision.buildpkg/sentinel"
if run_buildpkg collision > "$test_root/collision.out" 2> "$test_root/collision.err"; then
	printf '%s\n' 'unmarked workspace collision unexpectedly succeeded' >&2
	exit 1
fi
test -f "$build_root/collision.buildpkg/sentinel"
grep 'without a trusted FAILED marker' "$test_root/collision.err" >/dev/null

# A file named FAILED is not sufficient; its exact marker identity matters.
mkdir "$build_root/malformed.buildpkg"
printf '%s\n' wrong-marker > "$build_root/malformed.buildpkg/FAILED"
printf '%s\n' keep > "$build_root/malformed.buildpkg/sentinel"
if run_buildpkg malformed > "$test_root/malformed.out" 2> "$test_root/malformed.err"; then
	printf '%s\n' 'malformed FAILED marker unexpectedly authorized retry' >&2
	exit 1
fi
test -f "$build_root/malformed.buildpkg/sentinel"
grep 'FAILED marker is not trusted' "$test_root/malformed.err" >/dev/null

test -z "$(find "$build_root" "$incoming" -mindepth 1 -name '.*' -print -quit 2>/dev/null)"

# Stop any failed-workspace holders before the trap deletes the test tree;
# they self-terminate when their workspace disappears, but exit promptly here.
for holder in "$build_root"/*.buildpkg/overlay-holder.json; do
	[ -f "$holder" ] || continue
	pid=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$holder")
	kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
done
n=0
while [ "$n" -lt 100 ] && [ -n "$(grep -rls "upperdir=$build_root" /proc/[0-9]*/mountinfo 2>/dev/null)" ]; do
	n=$((n + 1))
	sleep 0.1
done
# The kernel creates the overlay workdir's internal work/ directory with
# mode 0000; restore owner permissions so the trap can delete the tree.
chmod -R u+rwX "$test_root" 2>/dev/null || true

# --- generation immutability belt (unit level) ------------------------------
# The belt fires inside promote() after a full build, which this fixture
# cannot afford against a mirrored live repository; exercise
# Transaction.guard_published_payload directly instead: staging an APK
# whose exact filename already exists in a non-live generation repository
# must be refused, declared or merely disk-discovered.
belt_root=$test_root/belt-generations
mkdir -p "$belt_root/oldgen/x86_64" "$belt_root/newgen/x86_64" "$belt_root/ghost/x86_64"
: > "$belt_root/oldgen/x86_64/belt-target-1.0-r1.apk"
: > "$belt_root/ghost/x86_64/Packages.adb"
: > "$belt_root/ghost/x86_64/belt-target-1.0-r1.apk"
python3 - "$buildpkg" "$belt_root" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_loader(
    "buildpkg_under_test",
    importlib.machinery.SourceFileLoader("buildpkg_under_test", sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
belt_root = pathlib.Path(sys.argv[2])
artifact = [pathlib.Path("/unused/belt-target-1.0-r1.apk")]


def controller(repo_names):
    transaction = module.Transaction.__new__(module.Transaction)
    transaction.config = {
        "SAPHIRA_REPO_DIR": str(belt_root), "SAPHIRA_REPO_NAMES": repo_names,
        "SAPHIRA_ARCH": "x86_64", "SAPHIRA_APK": "apk",
    }
    return transaction


# Declared older generation holding the NVR: refusal.
try:
    controller("oldgen newgen").guard_published_payload(artifact)
except module.BuildError as exc:
    message = str(exc)
    assert "refusing to stage belt-target-1.0-r1.apk" in message, message
    assert "generation repository 'oldgen'" in message, message
    assert "promote-repo" in message, message
else:
    raise SystemExit("belt: declared-generation collision was not refused")

# Undeclared but disk-discovered generation (index-bearing): refusal.
try:
    controller("newgen").guard_published_payload(artifact)
except module.BuildError as exc:
    message = str(exc)
    assert "generation repository 'ghost'" in message, message
else:
    raise SystemExit("belt: disk-discovered collision was not refused")

# Live view already ahead on the same version line: bump demand, never
# a promote remedy for the superseded archive revision.
live_ahead = belt_root / "newgen" / "x86_64" / "belt-target-1.0-r2.apk"
live_ahead.touch()
try:
    controller("oldgen newgen").guard_published_payload(artifact)
except module.BuildError as exc:
    message = str(exc)
    assert "already carries newer belt-target-1.0-r2.apk on the same version line" in message, message
    assert "never promote superseded archive revisions forward" in message, message
    assert "promote-repo" not in message, message
else:
    raise SystemExit("belt: behind-live collision was not refused")
live_ahead.unlink()

# Clean case (NVR published nowhere): staging proceeds.
controller("newgen").guard_published_payload(
    [pathlib.Path("/unused/belt-target-2.0-r1.apk")])
print()
PY

# --- recipe-parameterization env pass-through -------------------------------
# ${SAPHIRA_KERNEL_VERSION:-1} must reach the recipe inside both the
# resolvepkg metadata sandbox and the buildpkg build sandbox: with the env
# set, plan and transaction carry version 9.9 (both sandboxes must agree,
# otherwise the plan would schedule version 1 while the build produced 9.9).
recipe_header env-probe '' '' 1
sed -i 's/^pkgver=1$/pkgver=${SAPHIRA_KERNEL_VERSION:-1}/' "$recipes/env-probe/recipe.sh"
printf '%s\n' \
	'recipe_build() { :; }' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/env-probe"' \
	'	chmod 755 "$DESTDIR/usr/bin/env-probe"' \
	'}' >> "$recipes/env-probe/recipe.sh"
SAPHIRA_KERNEL_VERSION=9.9 run_buildpkg env-probe >/dev/null 2> "$test_root/env-probe.err"
test -n "$(find "$incoming" -mindepth 3 -maxdepth 3 -name 'env-probe-9.9-r1.apk')"
test -z "$(find "$incoming" -mindepth 3 -maxdepth 3 -name 'env-probe-1-r1.apk')"

# --- verified-source cache -------------------------------------------------
# A vendor=+sha256= recipe fetches once, verifies, populates the
# content-addressed cache, and builds. Deleting the origin then rebuilding
# at a new pkgrel must succeed from the cache alone: no re-download. A
# wrong digest fails the build before anything is cached.
#
# The origins are staged under the recipes tree (hidden dot-dir, never a
# recipe): /recipes is ro-mounted into the isolated build namespace, while
# anything else on the host (e.g. $test_root/origin) is invisible there,
# so a host-absolute file:// URL could never resolve. file:// keeps the
# test hermetic; the fetch->verify->cache machinery is transport-agnostic.
mkdir -p "$test_root/origin-content" "$recipes/.vendor-origin"
printf '%s\n' probe-payload > "$test_root/origin-content/probe.txt"
tar -C "$test_root" -cf "$recipes/.vendor-origin/vendor-probe-1.tar" origin-content
probe_sha=$(sha256sum "$recipes/.vendor-origin/vendor-probe-1.tar" | cut -d' ' -f1)
recipe_header vendor-probe '' '' 1
printf '%s\n' \
	'vendor=file:///recipes/.vendor-origin/vendor-probe-1.tar' \
	"sha256=$probe_sha" \
	'recipe_build() { test -f probe.txt; }' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/vendor-probe"' \
	'	chmod 755 "$DESTDIR/usr/bin/vendor-probe"' \
	'}' >> "$recipes/vendor-probe/recipe.sh"
run_buildpkg vendor-probe >/dev/null 2> "$test_root/vendor-probe.err"
test -n "$(find "$incoming" -mindepth 3 -maxdepth 3 -name 'vendor-probe-1-r1.apk')"
test -f "$test_root/source-cache/$probe_sha"
rm -f "$recipes/.vendor-origin/vendor-probe-1.tar"
sed -i 's/^pkgrel=1$/pkgrel=2/' "$recipes/vendor-probe/recipe.sh"
run_buildpkg vendor-probe >/dev/null 2> "$test_root/vendor-probe-r2.err"
test -n "$(find "$incoming" -mindepth 3 -maxdepth 3 -name 'vendor-probe-1-r2.apk')"
recipe_header vendor-bad '' '' 1
printf '%s\n' poisoned-payload > "$test_root/origin-content/probe.txt"
tar -C "$test_root" -cf "$recipes/.vendor-origin/vendor-bad-1.tar" origin-content
printf '%s\n' \
	'vendor=file:///recipes/.vendor-origin/vendor-bad-1.tar' \
	'sha256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' \
	'recipe_build() { :; }' \
	'recipe_install() { :; }' >> "$recipes/vendor-bad/recipe.sh"
if run_buildpkg vendor-bad > "$test_root/vendor-bad.out" 2> "$test_root/vendor-bad.err"; then
	printf '%s\n' 'digest mismatch unexpectedly built' >&2
	exit 1
fi
grep 'failed verification' "$build_root/vendor-bad.buildpkg/logs/buildpkg.log" >/dev/null
# Retire the deliberately-failed workspace through the trusted lifecycle
# (kills the overlay holder, fixes workdir perms, removes); otherwise the
# EXIT-trap cleanup below cannot delete the retained overlay workdir.
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$build_root \
	"$source_root/saphira-packager/files/cleanpkg" vendor-bad >/dev/null
test ! -e "$build_root/vendor-bad.buildpkg"

# --- source-cache fallback -------------------------------------------------
# Fresh-host bootstrap: when the configured persistent cache cannot even
# be provisioned (unwritable parent, e.g. sysfs here standing in for a
# root-owned /var/cache on a fresh host), the build must fall back to a
# disposable per-build cache - loudly - rather than dying with EACCES.
mkdir -p "$test_root/fallback-content"
printf '%s\n' fallback-payload > "$test_root/fallback-content/probe.txt"
tar -C "$test_root" -cf "$recipes/.vendor-origin/vendor-fallback-1.tar" fallback-content
fallback_sha=$(sha256sum "$recipes/.vendor-origin/vendor-fallback-1.tar" | cut -d' ' -f1)
recipe_header vendor-fallback '' '' 1
printf '%s\n' \
	'vendor=file:///recipes/.vendor-origin/vendor-fallback-1.tar' \
	"sha256=$fallback_sha" \
	'recipe_build() { test -f probe.txt; }' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/vendor-fallback"' \
	'	chmod 755 "$DESTDIR/usr/bin/vendor-fallback"' \
	'}' >> "$recipes/vendor-fallback/recipe.sh"
SAPHIRA_TEST_SOURCE_CACHE=/sys/saphira-source-cache-test \
	run_buildpkg vendor-fallback >/dev/null 2> "$test_root/vendor-fallback.err"
test -n "$(find "$incoming" -mindepth 3 -maxdepth 3 -name 'vendor-fallback-1-r1.apk')"
grep 'disposable per-build cache' "$test_root/vendor-fallback.err" >/dev/null
test ! -e /sys/saphira-source-cache-test

printf '%s\n' 'single-root isolation, graph-output, lifecycle, overlay base reuse, incoming transaction, verified-source cache, and source-cache fallback tests: OK'

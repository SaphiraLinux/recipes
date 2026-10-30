#!/bin/sh

# Closure-local dependency consumption: an entirely unpublished
# build-time chain (dep-a <- dep-b <- dep-c, none published) must build
# with a single buildpkg and no signing step in between.
#
# Downstream workers consume closure outputs through direct
# path-installs of the exact producer APKs into the transaction's
# shared merged root (buildpkg install_local_outputs: apk add
# /artifacts/<arch>/<name>-<version>.apk --allow-untrusted
# --force-non-repository) - never through a repository index, never
# signed, never published. Each downstream recipe_build guards on the
# upstream payload, so a broken handoff fails the build instead of
# silently building without the dependency. The staged ready
# transaction must remain unsigned (one final sign-apk-repo after the
# whole closure succeeds is the operator's publication boundary).

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s BUILDPKG\n' "$0" >&2
	exit 1
}

buildpkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$buildpkg")/../.." && pwd)
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-closure-deps-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
recipes=$test_root/recipes
build_root=$test_root/build
incoming=$test_root/incoming
mkdir -p "$recipes" "$build_root" "$incoming"
# Plan-phase identity gate reads the registry from the recipe root:
# the synthetic tree carries an empty one (no fixture declares
# identities; any fragment here would refuse before building).
mkdir -p "$recipes/saphira-baselayout/files"
printf '%s\n' '# name	type	id	primary-group	home	shell	supplementary-groups	init' > "$recipes/saphira-baselayout/files/accounts.tsv"

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
	SAPHIRA_HOST_RESOLV_CONF=/etc/resolv.conf SAPHIRA_HOST_HOSTS_FILE=/etc/hosts \
	SAPHIRA_BUILD_SEED='saphira-base-abi apk-tools bash libcap coreutils findutils pcre2 grep python3 ca-certificates curl tar musl musl-dev saphira-kernel-headers libxcrypt flex' \
	SAPHIRA_SOURCE_CACHE=${SAPHIRA_TEST_SOURCE_CACHE:-$test_root/source-cache} \
		"$buildpkg" "$@"
}

recipe_header()
{
	package=$1
	depends=$2
	mkdir -p "$recipes/$package"
	printf '%s\n' \
		'#!/bin/bash' \
		"pkgname=$package" \
		'pkgver=1' \
		'pkgrel=1' \
		'pkgarch=x86_64' \
		"pkgdesc='$package closure fixture'" \
		'license=MIT' \
		"origin=$package" \
		'repo=test' \
		'url=https://example.invalid/' \
		'depends=""' \
		"makedepends='$depends'" \
		"subpackages=''" > "$recipes/$package/recipe.sh"
}

recipe_header dep-a ''
printf '%s\n' \
	'recipe_build() { :; }' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin" "$DESTDIR/usr/share/dep-a"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/dep-a"' \
	'	chmod 755 "$DESTDIR/usr/bin/dep-a"' \
	'	printf "%s\n" provided > "$DESTDIR/usr/share/dep-a/provided"' \
	'}' >> "$recipes/dep-a/recipe.sh"

# dep-b consumes dep-a at BUILD time: both guards fail the build when
# the closure handoff is broken (binary on PATH, payload in the root).
recipe_header dep-b 'dep-a'
printf '%s\n' \
	'recipe_build() {' \
	'	command -v dep-a >/dev/null' \
	'	test -f /usr/share/dep-a/provided' \
	'}' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin" "$DESTDIR/usr/share/dep-b"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/dep-b"' \
	'	chmod 755 "$DESTDIR/usr/bin/dep-b"' \
	'	printf "%s\n" provided > "$DESTDIR/usr/share/dep-b/provided"' \
	'}' >> "$recipes/dep-b/recipe.sh"

recipe_header dep-c 'dep-b'
printf '%s\n' \
	'recipe_build() {' \
	'	command -v dep-b >/dev/null' \
	'	test -f /usr/share/dep-b/provided' \
	'}' \
	'recipe_install() {' \
	'	install -d "$DESTDIR/usr/bin"' \
	'	printf "%s\n" "#!/bin/sh" "exit 0" > "$DESTDIR/usr/bin/dep-c"' \
	'	chmod 755 "$DESTDIR/usr/bin/dep-c"' \
	'}' >> "$recipes/dep-c/recipe.sh"

host_before=$(sha256sum /lib/apk/db/installed /etc/apk/world)
test_repo_base=${SAPHIRA_TEST_REPO_DIR:-/out/stage4/packages}
repo_names=${SAPHIRA_TEST_REPO_NAMES:-hatchling}
live_repo=$test_repo_base/${repo_names##* }/x86_64
if [ ! -d "$live_repo" ]; then
	printf '%s\n' "closure-deps: live generation repository is missing: $live_repo" >&2
	exit 1
fi
# Precondition: none of the chain is published anywhere the test can see.
for name in dep-a dep-b dep-c; do
	test -z "$(find "$live_repo" -maxdepth 1 -name "$name-*.apk" -print -quit)"
done
repo_before=$(find "$live_repo" -maxdepth 1 -type f -printf '%f %s %T@\n' | sort | sha256sum)

# One build, no signing step anywhere in between.
if ! run_buildpkg dep-c; then
	sed -n '1,200p' "$build_root/dep-c.buildpkg/logs/buildpkg.log" >&2
	exit 1
fi
host_after=$(sha256sum /lib/apk/db/installed /etc/apk/world)
repo_after=$(find "$live_repo" -maxdepth 1 -type f -printf '%f %s %T@\n' | sort | sha256sum)
[ "$host_before" = "$host_after" ]
[ "$repo_before" = "$repo_after" ]

# Success removes the workspace; every locally-built producer receives its
# own authoritative transaction (target == producer), each carrying only
# its own outputs plus the full resolver plan and exact build-time closure
# hashes. The consumer never bundles dependencies as publishable outputs.
test ! -e "$build_root/dep-c.buildpkg"
for producer in dep-a dep-b dep-c; do
	set -- "$incoming/x86_64"/$producer-*-ready
	[ "$#" -eq 1 ] && [ -d "$1" ] || {
		printf '%s\n' "closure-deps: expected exactly one ready transaction for $producer" >&2
		exit 1
	}
done
ready_a=$(echo "$incoming"/x86_64/dep-a-*-ready)
ready_b=$(echo "$incoming"/x86_64/dep-b-*-ready)
ready_c=$(echo "$incoming"/x86_64/dep-c-*-ready)
test -f "$ready_a/dep-a-1-r1.apk"
test ! -e "$ready_a/dep-b-1-r1.apk"
test ! -e "$ready_a/dep-c-1-r1.apk"
test -f "$ready_b/dep-b-1-r1.apk"
test ! -e "$ready_b/dep-a-1-r1.apk"
test ! -e "$ready_b/dep-c-1-r1.apk"
test -f "$ready_c/dep-c-1-r1.apk"
test ! -e "$ready_c/dep-a-1-r1.apk"
test ! -e "$ready_c/dep-b-1-r1.apk"
python3 - "$ready_a/artifact-manifest.json" "$ready_b/artifact-manifest.json" "$ready_c/artifact-manifest.json" \
	"$ready_a/plan.json" "$ready_c/closure-hashes.json" <<'PY'
import json
import sys
for path in sys.argv[1:4]:
    with open(path, encoding="utf-8") as stream:
        manifest = json.load(stream)
    assert manifest["schema"] == "saphira-build-artifacts/v1"
    assert len(manifest["constructors"]) == 1
    assert manifest["constructors"][0]["constructor"] == "makepkg"
with open(sys.argv[1], encoding="utf-8") as stream:
    assert json.load(stream)["target"] == "dep-a"
with open(sys.argv[2], encoding="utf-8") as stream:
    assert json.load(stream)["target"] == "dep-b"
with open(sys.argv[3], encoding="utf-8") as stream:
    assert json.load(stream)["target"] == "dep-c"
with open(sys.argv[4], encoding="utf-8") as stream:
    plan = json.load(stream)
assert plan["schema"] == "saphira-build-plan/v1"
assert plan["target"] == "dep-c"
assert [b["producer"] for b in plan["builds"]] == ["dep-a", "dep-b", "dep-c"]
with open(sys.argv[5], encoding="utf-8") as stream:
    closure = json.load(stream)
assert closure["schema"] == "saphira-build-closure/v1"
assert closure["target"] == "dep-c"
PY
(CDPATH= cd -- "$ready_a" && sha256sum -c manifest.sha256 >/dev/null)
(CDPATH= cd -- "$ready_b" && sha256sum -c manifest.sha256 >/dev/null)
(CDPATH= cd -- "$ready_c" && sha256sum -c manifest.sha256 >/dev/null)

# The staged artifacts are valid APKs (allow-untrusted verifies) but
# remain UNSIGNED: plain verification must refuse every one of them,
# so the operator's final sign-apk-repo is still the publication gate.
for artifact in "$ready_a"/dep-a-1-r1.apk "$ready_b"/dep-b-1-r1.apk "$ready_c"/dep-c-1-r1.apk; do
	apk verify --allow-untrusted "$artifact" >/dev/null
	if apk verify "$artifact" >/dev/null 2>&1; then
		printf '%s\n' "closure-deps: staged artifact unexpectedly verifies signed: $artifact" >&2
		exit 1
	fi
done

# Stop any failed-workspace holders before the trap deletes the test tree.
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
chmod -R u+rwX "$test_root" 2>/dev/null || true

printf '%s\n' 'unpublished closure chain (dep-a <- dep-b <- dep-c, unsigned staging) tests: OK'

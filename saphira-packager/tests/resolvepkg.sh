#!/bin/sh

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s RESOLVER\n' "$0" >&2
	exit 1
}

resolver=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$resolver")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-resolver-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
recipes=$test_root/recipes
build_root=$test_root/build
mkdir -p "$recipes" "$build_root"

run_resolver()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_RECIPE_ROOT=$recipes \
	SAPHIRA_REFERENCE_RECIPE_ROOT=$test_root/reference \
	SAPHIRA_CPORTS_ROOT=$test_root/cports \
	SAPHIRA_BUILD_ROOT=$build_root \
	SAPHIRA_REPO_DIR=${SAPHIRA_TEST_REPO_DIR:-/out/stage4/packages} \
	SAPHIRA_REPO_NAMES=${SAPHIRA_TEST_REPO_NAMES:-hatchling} \
	SAPHIRA_TRUST_KEY=${SAPHIRA_TEST_TRUST_KEY:-/etc/apk/keys/akadata-repository.rsa.pub} \
	SAPHIRA_GENESIS_EXCLUDE=${SAPHIRA_TEST_GENESIS_EXCLUDE:-} \
	SAPHIRA_BINDIR=$source_root/saphira-packager/files \
		"$resolver" "$@"
}

recipe()
{
	package=$1
	version=$2
	dependencies=$3
	subpackages=${4-}
	mkdir -p "$recipes/$package"
	printf '%s\n' \
		'#!/bin/sh' \
		"pkgname=$package" \
		"pkgver=$version" \
		'pkgrel=1' \
		'pkgarch=x86_64' \
		"pkgdesc='$package fixture'" \
		'license=MIT' \
		"origin=$package" \
		'repo=test' \
		'url=https://example.invalid/' \
		"depends='$dependencies'" \
		'makedepends=""' \
		"subpackages='$subpackages'" \
		'recipe_build() { :; }' \
		'recipe_install() { :; }' > "$recipes/$package/recipe.sh"
}

assert_plan()
{
	plan=$1
	program=$2
	python3 - "$plan" "$program" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    plan = json.load(stream)
assert plan["schema"] == "saphira-build-plan/v1"
exec(sys.argv[2], {"plan": plan, "json": json})
PY
}

# Exact regression: repository acl-dev wins over the newer local ACL recipe
# (repository-first, regardless of revisions on either side). The local
# fixture pins r99 so the premise survives trusted-repository republishing.
recipe acl 2.3.2 '' 'acl-dev acl-doc'
sed -i 's/pkgrel=1/pkgrel=99/' "$recipes/acl/recipe.sh"
recipe unversioned-target 1 acl-dev
run_resolver unversioned-target > "$test_root/unversioned.json"
assert_plan "$test_root/unversioned.json" '
assert [node["producer"] for node in plan["builds"]] == ["unversioned-target"]
acl = next(node for node in plan["repository"] if node["name"] == "acl-dev")
assert acl["version"].startswith("2.3.2-r")
'

# Regression: an exact version pin without a revision (=7.1.5) is
# satisfied by any -rN of that base version already in the repository
# (apk dependency semantics). `apk version -t` orders 7.1.5-r1 > 7.1.5,
# so the resolver must not demand a rebuild of the producer.
recipe headers-pinned-consumer 1 'saphira-kernel-headers=7.1.5'
run_resolver headers-pinned-consumer > "$test_root/pinned-no-rel.json"
assert_plan "$test_root/pinned-no-rel.json" '
assert not any(
    node.get("name") == "saphira-kernel-headers"
    or node.get("producer") == "saphira-kernel-headers"
    for node in plan["builds"]
)
assert any(node["name"] == "saphira-kernel-headers" for node in plan["repository"])
assert next(
    node["version"]
    for node in plan["repository"]
    if node["name"] == "saphira-kernel-headers"
).startswith("7.1.5-r")
'

# A constraint the trusted repository cannot satisfy builds the local
# subpackage producer (repo currently serves acl-dev 2.3.2-rN with small N;
# the r99 fixture stays above it).
recipe constrained-target 1 'acl-dev>=2.3.2-r99'
run_resolver constrained-target > "$test_root/constrained.json"
assert_plan "$test_root/constrained.json" '
assert [node["producer"] for node in plan["builds"]] == ["acl", "constrained-target"]
acl = plan["builds"][0]
assert acl["required_outputs"] == ["acl-dev"]
assert not any(node["name"] == "acl-dev" for node in plan["repository"])
'

# An explicit top-level request always builds the current native recipe.
run_resolver acl > "$test_root/top-level.json"
assert_plan "$test_root/top-level.json" '
assert plan["target_producer"] == "acl"
assert plan["builds"][-1]["producer"] == "acl"
assert plan["builds"][-1]["version"] == "2.3.2-r99"
'

# Repository-only packages remain usable without native recipes.
recipe repository-only-target 1 attr
run_resolver repository-only-target > "$test_root/repository-only.json"
assert_plan "$test_root/repository-only.json" '
assert [node["producer"] for node in plan["builds"]] == ["repository-only-target"]
assert any(node["name"] == "attr" for node in plan["repository"])
'

# Producer/subpackage mapping and locally-built reuse are closure-local.
recipe local-producer 1 '' 'local-producer-dev local-producer-doc'
recipe local-consumer-a 1 'local-producer-dev>=1-r1'
recipe local-consumer-b 1 'local-producer-dev>=1-r1'
recipe local-target 1 'local-consumer-a local-consumer-b'
run_resolver local-target > "$test_root/local.json"
assert_plan "$test_root/local.json" '
names = [node["producer"] for node in plan["builds"]]
assert names == ["local-producer", "local-consumer-a", "local-consumer-b", "local-target"]
producer = plan["builds"][0]
assert producer["required_outputs"] == ["local-producer-dev"]
assert "local-producer-doc" in producer["outputs"]
'

# Deterministic topological ordering.
recipe topo-x 1 ''
recipe topo-y 1 ''
recipe topo-z 1 ''
recipe topo-c 1 'topo-x topo-y topo-z'
recipe topo-b 1 topo-c
recipe topo-q 1 ''
recipe topo-a 1 'topo-b topo-q'
run_resolver topo-a > "$test_root/topology-1.json"
run_resolver topo-a > "$test_root/topology-2.json"
cmp "$test_root/topology-1.json" "$test_root/topology-2.json"
assert_plan "$test_root/topology-1.json" '
assert [node["producer"] for node in plan["builds"]] == ["topo-x", "topo-y", "topo-z", "topo-c", "topo-b", "topo-q", "topo-a"]
'

# Cycles and unsupported constraints fail clearly.
recipe cycle-a 1 cycle-b
recipe cycle-b 1 cycle-a
if run_resolver cycle-a > "$test_root/cycle.json" 2> "$test_root/cycle.log"; then
	printf '%s\n' 'cycle test unexpectedly succeeded' >&2
	exit 1
fi
grep 'dependency cycle detected' "$test_root/cycle.log" >/dev/null
recipe unsupported-target 1 'attr!=2'
if run_resolver unsupported-target > "$test_root/unsupported.json" 2> "$test_root/unsupported.log"; then
	printf '%s\n' 'unsupported constraint unexpectedly succeeded' >&2
	exit 1
fi
grep 'unsupported dependency expression' "$test_root/unsupported.log" >/dev/null

# Exact -rN revision pins are rejected: repository metadata presents only
# the newest revision per package, so an exact revision pin couples the
# build to an obsolete snapshot the index no longer serves. Version-only
# pins (=7.1.5) and >=-rN floors stay legal (tested above).
recipe revision-pinned-target 1 'libtool=2.5.4-r1'
if run_resolver revision-pinned-target > "$test_root/revision-pin.json" 2> "$test_root/revision-pin.log"; then
	printf '%s\n' 'revision-pin test unexpectedly succeeded' >&2
	exit 1
fi
grep 'exact revision pin' "$test_root/revision-pin.log" >/dev/null

# Metadata shell code is contained: build functions are not called, Egg paths
# are not mounted writable, and unrelated recipes never enter the plan.
host_marker=/tmp/saphira-resolver-host-marker.$$
test ! -e "$host_marker"
recipe sandbox-target 1 ''
printf '%s\n' \
	"builtin printf sandbox > '$host_marker'" \
	'recipe_build() { builtin printf build-ran > /tmp/build-ran; }' \
	'recipe_install() { :; }' >> "$recipes/sandbox-target/recipe.sh"
run_resolver sandbox-target > "$test_root/sandbox.json"
test ! -e "$host_marker"
recipe unrelated-catalogue-entry 1 ''
run_resolver sandbox-target > "$test_root/closure.json"
assert_plan "$test_root/closure.json" '
encoded = json.dumps(plan, sort_keys=True)
assert "unrelated-catalogue-entry" not in encoded
assert len(plan["builds"]) == 1
'

test -z "$(find "$build_root" -mindepth 1 -name '.*' -print -quit)"

# --- generation lineage immutability guard ---------------------------------
# Fixture generations signed with a local test key: the older generation
# holds legacy-tool-1.0-r1 while the live generation does not. The resolver
# must refuse to rebuild a published NVR and demand promote-repo instead.
guard_keys=$test_root/guard-keys
guard_repos=$test_root/guard-repos
guard_stage=$test_root/guard-stage
guard_incoming=$test_root/guard-incoming
oldgen=$guard_repos/oldgen/x86_64
newgen=$guard_repos/newgen/x86_64
mkdir -p "$guard_keys" "$oldgen" "$newgen" "$guard_incoming" "$test_root/guard-makepkg-tmp"

openssl genrsa -traditional -out "$test_root/guard-signing.rsa" 2048 >/dev/null 2>&1
openssl rsa -in "$test_root/guard-signing.rsa" -pubout -out "$guard_keys/test-repository.rsa.pub" >/dev/null 2>&1

fabricate()
{
	name=$1
	version=$2
	stage=$guard_stage/$name
	mkdir -p "$stage/pkg/usr/bin"
	printf '#!/bin/sh\n' > "$stage/pkg/usr/bin/$name"
	python3 - "$stage/manifest.json" "$name" "$version" <<'PY'
import json, sys
path, name, version = sys.argv[1:4]
manifest = {
	"arch": "x86_64", "build_time": 1, "license": "MIT", "name": name,
	"origin": name,
	"outputs": [{"dependencies": [], "description": f"{name} fixture",
	             "name": name, "payload": "pkg"}],
	"schema": "saphira-stage-manifest/v1", "url": "https://example.invalid/",
	"version": version,
}
with open(path, "w", encoding="utf-8") as stream:
	json.dump(manifest, stream)
PY
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$guard_stage SAPHIRA_INCOMING_DIR=$guard_incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/guard-makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot \
		"$source_root/saphira-packager/files/makepkg" "$name" >/dev/null
}

index_repo()
{
	repo=$1
	apk mkndx --allow-untrusted --hash sha256-160 -o "$repo/Packages.adb" "$repo"/*.apk
	cp -- "$repo/Packages.adb" "$repo/APKINDEX.tar.gz"
	for index in "$repo/Packages.adb" "$repo/APKINDEX.tar.gz"; do
		apk adbsign --allow-untrusted --sign-key "$test_root/guard-signing.rsa" "$index"
		apk verify --keys-dir "$guard_keys" "$index"
	done
}

fabricate legacy-tool 1.0-r1
fabricate live-helper 2.0-r1
cp "$guard_incoming/x86_64/legacy-tool-1.0-r1.apk" "$oldgen/"
cp "$guard_incoming/x86_64/live-helper-2.0-r1.apk" "$newgen/"
index_repo "$oldgen"
index_repo "$newgen"

run_guard_resolver()
{
	SAPHIRA_TEST_REPO_DIR=$guard_repos \
	SAPHIRA_TEST_REPO_NAMES=${SAPHIRA_GUARD_REPO_NAMES:-oldgen newgen} \
	SAPHIRA_TEST_TRUST_KEY=$guard_keys/test-repository.rsa.pub \
		run_resolver "$@"
}

# Rebuilding an NVR that exists only in an older generation fails with a
# generation-lineage error naming promote-repo as the sanctioned repair.
recipe legacy-tool 1.0 ''
if run_guard_resolver legacy-tool > "$test_root/lineage.out" 2> "$test_root/lineage.err"; then
	printf '%s\n' 'lineage guard test unexpectedly scheduled a rebuild' >&2
	exit 1
fi
grep 'generation lineage repair required: legacy-tool-1.0-r1 already exists in generation repository .oldgen.' \
	"$test_root/lineage.err" >/dev/null
grep 'promote-repo oldgen newgen legacy-tool-1.0-r1' "$test_root/lineage.err" >/dev/null

# A genuinely bumped revision (new NVR) still builds normally.
sed -i 's/pkgrel=1/pkgrel=2/' "$recipes/legacy-tool/recipe.sh"
run_guard_resolver legacy-tool > "$test_root/lineage-bumped.json"
assert_plan "$test_root/lineage-bumped.json" '
assert [node["producer"] for node in plan["builds"]] == ["legacy-tool"]
assert plan["builds"][0]["version"] == "1.0-r2"
'

# A recipe behind the live view on the same version line is refused with a
# bump demand, never a promote remedy: superseded archive revisions must
# not move forward into the live view.
rm -rf "$guard_stage/legacy-tool"
fabricate legacy-tool 1.0-r2
cp "$guard_incoming/x86_64/legacy-tool-1.0-r2.apk" "$newgen/"
index_repo "$newgen"
recipe legacy-tool 1.0 ''
if run_guard_resolver legacy-tool > "$test_root/behind.out" 2> "$test_root/behind.err"; then
	printf '%s\n' 'behind-live guard test unexpectedly scheduled a rebuild' >&2
	exit 1
fi
grep 'already carries newer legacy-tool-1.0-r2 on the same version line' \
	"$test_root/behind.err" >/dev/null
grep 'never promote superseded archive revisions forward' \
	"$test_root/behind.err" >/dev/null
if grep 'promote-repo oldgen newgen' "$test_root/behind.err" >/dev/null; then
	printf '%s\n' 'behind-live guard test wrongly prescribed promotion' >&2
	exit 1
fi
# Restore the fixture so downstream drift/retired tests see the original
# oldgen-r1 / live-empty shape.
rm "$newgen/legacy-tool-1.0-r2.apk"
index_repo "$newgen"
recipe legacy-tool 1.0 ''

# Retired names (SAPHIRA_GENESIS_EXCLUDE) demand dependency migration,
# never promotion.
recipe legacy-tool 1.0 ''
if SAPHIRA_TEST_GENESIS_EXCLUDE=legacy-tool run_guard_resolver legacy-tool \
		> "$test_root/retired.out" 2> "$test_root/retired.err"; then
	printf '%s\n' 'retired-name guard test unexpectedly scheduled a rebuild' >&2
	exit 1
fi
grep 'retired via SAPHIRA_GENESIS_EXCLUDE' "$test_root/retired.err" >/dev/null

# The guard also scans generation directories that exist on disk but are
# no longer declared in SAPHIRA_REPO_NAMES (defensive config-drift check).
if SAPHIRA_GUARD_REPO_NAMES=newgen run_guard_resolver legacy-tool \
		> "$test_root/drift.out" 2> "$test_root/drift.err"; then
	printf '%s\n' 'config-drift guard test unexpectedly scheduled a rebuild' >&2
	exit 1
fi
grep 'generation lineage repair required: legacy-tool-1.0-r1 already exists in generation repository .oldgen.' \
	"$test_root/drift.err" >/dev/null

# Recipe-parameterization environment reaches the metadata sandbox: the
# plan's producer version follows SAPHIRA_KERNEL_VERSION when set, and the
# default applies when unset.
recipe env-probe 1 ''
sed -i 's/^pkgver=1$/pkgver=${SAPHIRA_KERNEL_VERSION:-1}/' "$recipes/env-probe/recipe.sh"
run_resolver env-probe > "$test_root/envprobe-default.json"
assert_plan "$test_root/envprobe-default.json" 'assert plan["builds"][0]["version"] == "1-r1"'
SAPHIRA_KERNEL_VERSION=9.9 run_resolver env-probe > "$test_root/envprobe-override.json"
assert_plan "$test_root/envprobe-override.json" 'assert plan["builds"][0]["version"] == "9.9-r1"'

printf '%s\n' 'resolvepkg closure, repository precedence, and sandbox tests: OK'

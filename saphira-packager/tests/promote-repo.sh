#!/bin/sh

set -eu

[ "$#" -eq 3 ] || {
	printf 'usage: %s PROMOTE-REPO MAKEPKG SIGN-APK-REPO\n' "$0" >&2
	exit 1
}

promote_repo=$1
makepkg=$2
sign_repo=$3
source_root=$(CDPATH= cd -- "$(dirname -- "$promote_repo")/../.." && pwd)
test_root=$(mktemp -d /tmp/saphira-promote-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
incoming=$test_root/incoming/x86_64
stage=$test_root/stage
artifacts=$test_root/artifacts
keys=$test_root/keys
mkdir -p "$test_root/repository/hatchling/x86_64" "$test_root/repository/hatched/x86_64" \
	"$test_root/repository/conflict/x86_64" "$test_root/repository/conflict2/x86_64" \
	"$incoming" "$artifacts" "$keys" "$test_root/package-tmp"

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

run_promoter()
{
	# SUDO_UID/SAPHIRA_REPO_GROUP exercise the ownership-normalization path
	# (inside the user namespace uid 0 is the only mapped target; the real
	# sudo chown to the invoking user is verified on Egg).
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$test_root/repository \
	SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$promote_repo" "$@"
}

build_unverified()
{
	# Same NVR as an existing package but genuinely different content,
	# left UNSIGNED (staged, never published).
	package=$1
	version=$2
	mkdir -p "$stage/$package-$version-alt/pkg/usr/bin"
	printf '%s\n' tampered > "$stage/$package-$version-alt/pkg/usr/bin/$package"
	printf '%s' "{\"arch\":\"x86_64\",\"build_time\":2,\"license\":\"MIT\",\"name\":\"$package-$version-alt\",\"origin\":\"$package\",\"outputs\":[{\"dependencies\":[],\"description\":\"$package\",\"name\":\"$package\",\"payload\":\"pkg\"}],\"schema\":\"saphira-stage-manifest/v1\",\"url\":\"https://example.invalid/\",\"version\":\"$version\"}" \
		> "$stage/$package-$version-alt/manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$test_root/tampered \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$package-$version-alt" >/dev/null
}

index_dir()
{
	repo=$1
	apk mkndx --allow-untrusted --hash sha256-160 -o "$repo/Packages.adb" "$repo"/*.apk >/dev/null
	cp "$repo/Packages.adb" "$repo/APKINDEX.tar.gz"
	apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" \
		"$repo/Packages.adb" "$repo/APKINDEX.tar.gz" >/dev/null 2>&1 || true
	for index in Packages.adb APKINDEX.tar.gz; do
		apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$repo/$index" >/dev/null
	done
}

# hatchling holds make-9-r1 (published via the normal publication path, so
# the APK is signed); hatched is a seeded generation already holding
# attr-1-r0, so index regeneration must retain both packages.
build_and_stage make 9-r1
build_and_stage attr 1-r0
run_signer >/dev/null
cp "$test_root/repository/hatchling/x86_64/attr-1-r0.apk" "$test_root/repository/hatched/x86_64/"
index_dir "$test_root/repository/hatched/x86_64"
hatched=$test_root/repository/hatched/x86_64

run_promoter hatchling hatched make-9-r1 > "$test_root/promote.out"
cmp -s "$test_root/repository/hatchling/x86_64/make-9-r1.apk" "$hatched/make-9-r1.apk"
apk verify --keys-dir "$keys" "$hatched/make-9-r1.apk"
apk verify --keys-dir "$keys" "$hatched/Packages.adb"
apk verify --keys-dir "$keys" "$hatched/APKINDEX.tar.gz"
[ "$(apk adbdump "$hatched/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 2 ]
test -f "$test_root/repository/promote-journal.jsonl"
grep -q '"nvr":"make-9-r1"' "$test_root/repository/promote-journal.jsonl"
test -z "$(find "$hatched" \( -name '*.publishing-*' -o -name '*.promoting-*' \) -print -quit)"

# Idempotent: re-promoting identical bytes is a no-op that neither rewrites
# the package nor regenerates the indexes.
index_sha=$(sha256sum "$hatched/Packages.adb" | cut -d' ' -f1)
run_promoter hatchling hatched make-9-r1 > "$test_root/idempotent.out"
grep 'already present (identical bytes): make-9-r1' "$test_root/idempotent.out" >/dev/null
[ "$index_sha" = "$(sha256sum "$hatched/Packages.adb" | cut -d' ' -f1)" ]

# A destination filename whose bytes differ is refused outright: the source
# generation conflict2 holds a genuinely different, unsigned build of the
# same NVR; conflict holds the original bytes at the destination.
build_unverified make 9-r1
tampered=$test_root/tampered/x86_64/make-9-r1.apk
if cmp -s "$tampered" "$test_root/repository/hatchling/x86_64/make-9-r1.apk"; then
	printf '%s\n' 'tampered fixture unexpectedly matches the published bytes' >&2
	exit 1
fi
cp "$test_root/repository/hatchling/x86_64/make-9-r1.apk" "$test_root/repository/conflict/x86_64/"
# Sign the tampered build with the same repository key so source
# verification passes and the immutability refusal is what fires.
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$tampered" >/dev/null
cp "$tampered" "$test_root/repository/conflict2/x86_64/"
index_dir "$test_root/repository/conflict2/x86_64"
if run_promoter conflict2 conflict make-9-r1 > "$test_root/refusal.out" 2> "$test_root/refusal.err"; then
	printf '%s\n' 'conflicting-content promotion unexpectedly succeeded' >&2
	exit 1
fi
grep 'published filename is immutable and has different content: make-9-r1' "$test_root/refusal.err" >/dev/null

# A source package that fails repository-key verification is refused.
build_and_stage unbound 2-r0
# unbound-2-r0 was staged but never published/signed; place the unsigned APK
# in the conflict generation.
cp "$artifacts/x86_64/unbound-2-r0.apk" "$test_root/repository/conflict/x86_64/"
apk mkndx --allow-untrusted --hash sha256-160 \
	-o "$test_root/repository/conflict/x86_64/Packages.adb" \
	"$test_root/repository/conflict/x86_64/"*.apk >/dev/null
cp "$test_root/repository/conflict/x86_64/Packages.adb" "$test_root/repository/conflict/x86_64/APKINDEX.tar.gz"
if run_promoter conflict hatched unbound-2-r0 > "$test_root/unverified.out" 2> "$test_root/unverified.err"; then
	printf '%s\n' 'unverified source unexpectedly promoted' >&2
	exit 1
fi
grep 'fails repository-key verification' "$test_root/unverified.err" >/dev/null

# An NVR missing from the source generation is refused.
if run_promoter hatchling hatched absent-1.0-r0 > "$test_root/missing.out" 2> "$test_root/missing.err"; then
	printf '%s\n' 'absent NVR unexpectedly promoted' >&2
	exit 1
fi
grep 'source package not found' "$test_root/missing.err" >/dev/null

# Self-promotion is refused.
if run_promoter hatchling hatchling make-9-r1 > "$test_root/self.out" 2> "$test_root/self.err"; then
	printf '%s\n' 'self-promotion unexpectedly succeeded' >&2
	exit 1
fi
grep 'source and destination generation are both' "$test_root/self.err" >/dev/null

printf '%s\n' 'promote-repo: verified exact-byte promotion, idempotence, immutability refusal, and verification refusal tests: OK'

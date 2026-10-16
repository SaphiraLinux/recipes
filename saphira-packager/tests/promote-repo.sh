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
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-promote-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
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

# SQLite era: publishing generations need their repository.db before
# the signer runs (test genesis, mirroring what seed-repo does in
# production for the repositories it births).
init_repo_db()
{
	python3 - "$source_root/saphira-packager/files/repo_db.py" "$1" "$2" "$3" <<'PY'
import os
import sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import repo_db
conn = repo_db.connect(os.path.join(sys.argv[2], "repository.db"))
repo_db.init_db(conn, sys.argv[3], sys.argv[4] == "1")
conn.commit()
conn.close()
PY
}
init_repo_db "$test_root/repository/hatchling/x86_64" hatchling 1

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
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$ready/package-seed.json"
	printf '%s\n' "{\"schema\":\"saphira-build-artifacts/v1\",\"target\":\"$producer\",\"constructors\":[{\"constructor\":\"makepkg\",\"producer\":\"$producer\"}],\"package_seed\":{\"schema\":\"saphira-package-seed/v1\",\"generation\":\"test\",\"seed\":[\"test\"],\"resolved\":[]}}" > "$ready/artifact-manifest.json"
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
# hatched is a hand-seeded generation: give it a ledger matching its
# contents (init + sync, no carriers — a current view, so history is
# explicitly incomplete), mirroring seed-repo behavior.
python3 - "$source_root/saphira-packager/files/repo_db.py" "$hatched" <<'PY'
import os
import sys
sys.path.insert(0, os.path.dirname(sys.argv[1]))
import repo_db
repo = sys.argv[2]
census_data = repo_db.census("apk", repo)
assert repo_db.fragment_carriers(census_data) == []
conn = repo_db.connect(os.path.join(repo, "repository.db"))
repo_db.init_db(conn, "hatched", False)
repo_db.sync_packages(conn, census_data, {}, "apk", repo_db.utcnow())
repo_db.set_meta(conn, "last_audit", repo_db.utcnow())
conn.commit()
conn.close()
PY
chmod 664 "$hatched/repository.db"

run_promoter hatchling hatched make-9-r1 > "$test_root/promote.out"
cmp -s "$test_root/repository/hatchling/x86_64/make-9-r1.apk" "$hatched/make-9-r1.apk"
python3 - "$hatched/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
assert ("make", "9-r1") in {(r[0], r[1]) for r in conn.execute("SELECT name, version FROM packages")}
assert ("attr", "1-r0") in {(r[0], r[1]) for r in conn.execute("SELECT name, version FROM packages")}
PY
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

# Declaration carriers traverse the promote path: extraction derives
# manifest-schema receipts (accounts incl. the sysusers mechanism flag,
# fhs, caps) so the shared gate sees exactly what the build recorded.
build_carrier_pkg()
{
	kind=$1
	package=$2
	version=$3
	producer=$package-$version
	mkdir -p "$stage/$producer/pkg/usr/bin"
	printf '%s\n' "$package" > "$stage/$producer/pkg/usr/bin/$package"
	case $kind in
	sysusers-static)
		mkdir -p "$stage/$producer/pkg/usr/share/saphira/accounts.d" \
			"$stage/$producer/pkg/usr/lib/sysusers.d"
		printf '%s\n' 'sysusers' > "$stage/$producer/pkg/usr/share/saphira/accounts.d/$package"
		printf '%s\n' 'u! natown 680 "Nat Owner"' > "$stage/$producer/pkg/usr/lib/sysusers.d/$package.conf"
		receipt_accounts='{"users":[{"name":"natown","uid":"680","primary":"natown","home":"","shell":""}],"groups":[{"name":"natown","gid":"680"}],"dirs":[],"files":[],"sysusers":true}'
		receipt_fhs='{"dirs":[],"replaces":[],"removals":[]}'
		;;
	sysusers-dynamic)
		mkdir -p "$stage/$producer/pkg/usr/share/saphira/accounts.d" \
			"$stage/$producer/pkg/usr/lib/sysusers.d"
		printf '%s\n' 'sysusers' > "$stage/$producer/pkg/usr/share/saphira/accounts.d/$package"
		printf '%s\n' 'u dynuser - "Dyn"' > "$stage/$producer/pkg/usr/lib/sysusers.d/$package.conf"
		receipt_accounts='{"users":[],"groups":[],"dirs":[],"files":[],"sysusers":true}'
		receipt_fhs='{"dirs":[],"replaces":[],"removals":[]}'
		;;
	fhs)
		mkdir -p "$stage/$producer/pkg/usr/share/saphira/fhs.d"
		printf 'dir /var/run/%s 0755 root root\n' "$package" > "$stage/$producer/pkg/usr/share/saphira/fhs.d/$package"
		receipt_accounts='{"users":[],"groups":[],"dirs":[],"files":[]}'
		receipt_fhs="{\"dirs\":[{\"path\":\"/var/run/$package\",\"mode\":\"0755\",\"owner\":\"root\",\"group\":\"root\"}],\"replaces\":[],\"removals\":[]}"
		;;
	*)
		printf '%s\n' "unknown carrier kind: $kind" >&2
		exit 1
		;;
	esac
	printf '%s' "{\"arch\":\"x86_64\",\"build_time\":1,\"license\":\"MIT\",\"name\":\"$producer\",\"origin\":\"$package\",\"outputs\":[{\"dependencies\":[],\"description\":\"$package\",\"name\":\"$package\",\"payload\":\"pkg\"}],\"schema\":\"saphira-stage-manifest/v1\",\"url\":\"https://example.invalid/\",\"version\":\"$version\"}" \
		> "$stage/$producer/manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$producer" >/dev/null
	ready=$incoming/$producer-ready
	mkdir "$ready"
	cp "$artifacts/x86_64/$package-$version.apk" "$ready/"
	apksha=$(sha256sum "$ready/$package-$version.apk" | cut -d' ' -f1)
	printf '%s\n' "$producer" > "$ready/target"
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$ready/package-seed.json"
	printf '%s\n' "{\"schema\":\"saphira-build-artifacts/v1\",\"target\":\"$producer\",\"constructors\":[{\"constructor\":\"makepkg\",\"producer\":\"$producer\",\"artifacts\":[{\"name\":\"$package\",\"version\":\"$version\",\"artifact\":\"$package-$version.apk\",\"sha256\":\"$apksha\",\"backend\":\"userns-maproot\",\"accounts\":$receipt_accounts,\"fhs\":$receipt_fhs}]}],\"package_seed\":{\"schema\":\"saphira-package-seed/v1\",\"generation\":\"test\",\"seed\":[\"test\"],\"resolved\":[]}}" > "$ready/artifact-manifest.json"
	(CDPATH= cd -- "$ready" && sha256sum "$package-$version.apk" > manifest.sha256)
}

# A sysusers-native package with static IDs promotes (census parity).
# Declaration extraction installs the carrier closure from the
# destination repo, so stub the base providers the generated callers
# depend on (mirrors a real generation, which always carries them).
for stub in "bash 1-r1" "coreutils 1-r1" "saphira-base-accounts 0.1-r1" "saphira-baselayout 0.1-r1"; do
	set -- $stub
	build_and_stage "$1" "$2"
done
run_signer >/dev/null
for stub in bash-1-r1 coreutils-1-r1 saphira-base-accounts-0.1-r1 saphira-baselayout-0.1-r1; do
	run_promoter hatchling hatched "$stub" > "$test_root/promote-$stub.out"
done
build_carrier_pkg sysusers-static natpubsvc 1-r1
# A sysusers-native package with only dynamic IDs promotes: the stanza
# is the declaration even when zero static IDs parse out (this refused
# before the derivation carried the mechanism flag).
build_carrier_pkg sysusers-dynamic dynsvc 1-r1
# An fhs.d carrier promotes (its migration declaration rides the same
# isolated-install extraction instead of being dropped).
build_carrier_pkg fhs fhssvc 1-r1
run_signer >/dev/null
for nvr in natpubsvc-1-r1 dynsvc-1-r1 fhssvc-1-r1; do
	run_promoter hatchling hatched "$nvr" > "$test_root/promote-$nvr.out"
	test -f "$hatched/$nvr.apk"
	grep -q "\"nvr\":\"$nvr\"" "$test_root/repository/promote-journal.jsonl"
	grep 'staged '"$nvr"' for promotion' "$test_root/promote-$nvr.out" >/dev/null
	grep -q 'promote-repo: promoted '"$nvr"': hatchling -> hatched' "$test_root/promote-$nvr.out"
done
python3 - "$hatched/repository.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
names = {(r[0], r[1]) for r in conn.execute("SELECT name, version FROM packages WHERE is_newest=1")}
assert ("natpubsvc", "1-r1") in names, "natpubsvc not live"
assert ("dynsvc", "1-r1") in names, "dynsvc not live"
assert ("fhssvc", "1-r1") in names, "fhssvc not live"
assert ("natown", "680") in {(r[0], str(r[1])) for r in conn.execute("SELECT name, gid FROM groups")}, "native group not ledgered"
PY
[ "$(apk adbdump "$hatched/Packages.adb" | awk '/^  - name: / { count++ } END { print count + 0 }')" -eq 9 ]

# A refused promotion leaves the destination byte-identical and never
# prints success wording: collide-1-r1 claims usr/bin/make, which live
# make-9-r1 already owns as an active r1+ claim, so the shared gate
# refuses after staging. (An r0-owned path would NOT refuse: r0 claims
# are inadmissible in the live view by design, hence make and not the
# hand-seeded r0 attr here.) The colliding package is signed directly
# into its own source generation: the shared sign gate would correctly
# refuse it in any generation already holding make.
mkdir -p "$stage/collide-1-r1/pkg/usr/bin"
printf '%s\n' colliding > "$stage/collide-1-r1/pkg/usr/bin/make"
printf '%s' '{"arch":"x86_64","build_time":1,"license":"MIT","name":"collide-1-r1","origin":"collide","outputs":[{"dependencies":[],"description":"collide","name":"collide","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"1-r1"}' \
	> "$stage/collide-1-r1/manifest.json"
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" collide-1-r1 >/dev/null
mkdir -p "$test_root/repository/srccollide/x86_64"
apk adbsign --allow-untrusted --sign-key "$test_root/test-repository.rsa" "$artifacts/x86_64/collide-1-r1.apk" >/dev/null
cp "$artifacts/x86_64/collide-1-r1.apk" "$test_root/repository/srccollide/x86_64/"
index_dir "$test_root/repository/srccollide/x86_64"
(CDPATH= cd -- "$hatched" && find . -type f -not -name 'repository.db*' | sort | xargs sha256sum > "$test_root/hatched-before.sha256")
sqlite3 "$hatched/repository.db" .dump > "$test_root/hatched-before.sql"
index_before=$(sha256sum "$hatched/Packages.adb" | cut -d' ' -f1)
if run_promoter srccollide hatched collide-1-r1 > "$test_root/collide.out" 2> "$test_root/collide.err"; then
	printf '%s\n' 'colliding promotion unexpectedly succeeded' >&2
	exit 1
fi
grep 'staged collide-1-r1 for promotion' "$test_root/collide.out" >/dev/null
! grep -q 'promote-repo: promoted collide-1-r1' "$test_root/collide.out"
test ! -f "$hatched/collide-1-r1.apk"
(CDPATH= cd -- "$hatched" && find . -type f -not -name 'repository.db*' | sort | xargs sha256sum > "$test_root/hatched-after.sha256")
sqlite3 "$hatched/repository.db" .dump > "$test_root/hatched-after.sql"
cmp -s "$test_root/hatched-before.sha256" "$test_root/hatched-after.sha256"
cmp -s "$test_root/hatched-before.sql" "$test_root/hatched-after.sql"
[ "$index_before" = "$(sha256sum "$hatched/Packages.adb" | cut -d' ' -f1)" ]
test -z "$(find "$hatched" \( -name '*.publishing-*' -o -name '*.promoting-*' \) -print -quit)"

printf '%s\n' 'promote-repo: verified exact-byte promotion, idempotence, immutability refusal, and verification refusal tests: OK'

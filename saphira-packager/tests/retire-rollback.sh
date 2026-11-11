#!/bin/sh

# retire-rollback.sh — exercises the reversible-retirement mechanism in
# sign-apk-repo without touching production repositories.
#
# Covers, hermetically (scratch repo, generated keys, unshare-rootless):
#   1. ordinary same-family pruning moves (never deletes) superseded NVRs
#      into the per-generation .retired archive and journals the move;
#   2. unrelated-family retirement fails closed without
#      --approve-unrelated-retirement and proceeds with it;
#   3. --rollback-last restores exact bytes + index + DB and removes the
#      files the publication added (no rebuilds);
#   4. a mid-publication failure restores moved files via the EXIT trap
#      (SAPHIRA_TEST_FAIL_AFTER_RETIRE hook) leaving rows untouched;
#   5. the full audit explicitly lists added and removed ledger rows;
#   6. --reap-retired lists without approval and deletes only with it,
#      never touching live APKs.
#
# usage: retire-rollback.sh SIGN-APK-REPO MAKEPKG CHECKPKG

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
test_root=$(mktemp -d "$test_tmp_base/saphira-retire-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
repo=$test_root/repository
gen_old=$repo/genold/x86_64
gen_live=$repo/genlive/x86_64
retired_dir=$repo/genlive/.retired
incoming=$test_root/incoming/x86_64
stage=$test_root/stage
artifacts=$test_root/artifacts
keys=$test_root/keys
mkdir -p "$gen_old" "$gen_live" "$incoming" "$stage/retireme/pkg/usr/bin" \
	"$stage/other/pkg/usr/bin" "$artifacts" "$keys" "$test_root/package-tmp"

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
init_repo_db "$gen_old" genold
init_repo_db "$gen_live" genlive

# Build fixture package NAME at VERSION-REL (e.g. retireme 1-r1) with a
# trivial payload, mirroring publication.sh's makepkg invocation.
build_fixture()
{
	_name=$1 _ver=$2
	_rdir=$stage/$_name
	mkdir -p "$_rdir/pkg/usr/bin"
	printf '%s\n' fake > "$_rdir/pkg/usr/bin/$_name"
	printf '%s\n' '{"arch":"x86_64","build_time":1,"license":"GPL-3.0-or-later","name":"'"$_name"'","origin":"'"$_name"'","outputs":[{"dependencies":[],"description":"retire test","name":"'"$_name"'","payload":"pkg"}],"schema":"saphira-stage-manifest/v1","url":"https://example.invalid/","version":"'"$_ver"'"}' > "$_rdir/manifest.json"
	rm -f "$_rdir/artifact-manifest.json"
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$stage SAPHIRA_INCOMING_DIR=$artifacts \
	SAPHIRA_PACKAGE_TMP=$test_root/makepkg-tmp SAPHIRA_FAKEROOT_BOOTSTRAP=1 \
	SAPHIRA_BOOTSTRAP_TARGET=fakeroot "$makepkg" "$_name" >/dev/null
}

# Stage a built NVR as a ready transaction, mirroring publication.sh.
stage_fixture()
{
	_name=$1 _ver=$2
	_nvr=$_name-$_ver
	_ready=$incoming/$_nvr-fixture-ready
	mkdir -p "$_ready"
	cp "$artifacts/x86_64/$_nvr.apk" "$_ready/"
	printf '%s\n' "$_name" > "$_ready/target"
	printf '%s\n' '{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}' > "$_ready/package-seed.json"
	printf '%s\n' '{"schema":"saphira-build-artifacts/v1","target":"'"$_name"'","constructors":[{"constructor":"makepkg","producer":"'"$_name"'","package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}],"package_seed":{"schema":"saphira-package-seed/v1","generation":"test","seed":["test"],"resolved":[]}}' > "$_ready/artifact-manifest.json"
	(CDPATH= cd -- "$_ready" && sha256sum "$_nvr.apk" > manifest.sha256)
}

run_signer()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_REPO_DIR=$repo SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp SAPHIRA_SIGN_KEY=$test_root/test-repository.rsa \
	SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub SAPHIRA_REPO_NAMES="genold genlive" \
	SUDO_UID=0 SAPHIRA_REPO_GROUP=root \
		unshare --map-root-user "$sign_repo" "$@"
}

live_nvrs()
{
	apk adbdump "$gen_live/Packages.adb" 2>/dev/null | awk '/^  - name: / { n=$3 } /^    version: / { print n"-"$2 }' | sort -u
}

journal_last_pubid()
{
	python3 -c 'import json,sys; pubs=[json.loads(l) for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("action")=="published"]; print(pubs[-1]["publication_id"])' "$repo/retire-journal.jsonl"
}

# --- Phase 1: ordinary same-family pruning archives, never deletes. ---
build_fixture retireme 1-r1
stage_fixture retireme 1-r1
run_signer >/dev/null
build_fixture retireme 1-r2
stage_fixture retireme 1-r2
run_signer >/dev/null
[ "$(live_nvrs | wc -l)" -eq 2 ]
r1sha=$(sha256sum "$gen_live/retireme-1-r1.apk" | awk '{ print $1 }')
build_fixture retireme 1-r3
stage_fixture retireme 1-r3
run_signer >/dev/null
[ "$(live_nvrs)" = "$(printf 'retireme-1-r2\nretireme-1-r3')" ]
test -f "$retired_dir/retireme-1-r1.apk"
[ "$(sha256sum "$retired_dir/retireme-1-r1.apk" | awk '{ print $1 }')" = "$r1sha" ]
test ! -e "$gen_live/retireme-1-r1.apk"
test -f "$repo/retire-journal.jsonl"
grep -q '"action":"published"' "$repo/retire-journal.jsonl"
echo "phase 1 ok: same-family prune archived, journaled"

# --- Phase 2: unrelated retirement fails closed, proceeds with approval. ---
export SAPHIRA_RETAIN_GENERATIONS=1
build_fixture other 1-r1
stage_fixture other 1-r1
if run_signer >/dev/null 2>"$test_root/refuse.err"; then
	echo "phase 2 FAILED: unrelated retirement was not refused" >&2
	exit 1
fi
grep -q 'retire set touches families absent from the staged set' "$test_root/refuse.err"
grep -q 'retireme' "$test_root/refuse.err"
test ! -e "$retired_dir/retireme-1-r2.apk"
# Refusal is whole-run: the staged package is not published either.
[ "$(live_nvrs)" = "$(printf 'retireme-1-r2\nretireme-1-r3')" ]
run_signer --approve-unrelated-retirement >/dev/null
[ "$(live_nvrs)" = "$(printf 'other-1-r1\nretireme-1-r3')" ]
test -f "$retired_dir/retireme-1-r2.apk"
unset SAPHIRA_RETAIN_GENERATIONS
echo "phase 2 ok: unrelated retire refused, then approved"

# --- Phase 3: rollback restores bytes and removes added files. ---
r3sha=$(sha256sum "$gen_live/retireme-1-r3.apk" | awk '{ print $1 }')
pubid=$(journal_last_pubid)
run_signer --rollback-publish "$pubid" >"$test_root/rollback.out" 2>&1
grep -q 'restored 1 retired APK(s)' "$test_root/rollback.out"
[ "$(live_nvrs)" = "$(printf 'retireme-1-r2\nretireme-1-r3')" ]
[ "$(sha256sum "$gen_live/retireme-1-r3.apk" | awk '{ print $1 }')" = "$r3sha" ]
test ! -e "$gen_live/other-1-r1.apk"
echo "phase 3 ok: rollback restored retired bytes, removed added files"

# --- Phase 4: mid-publication failure restores moved files, rows intact. ---
build_fixture retireme 1-r4
stage_fixture retireme 1-r4
if SAPHIRA_TEST_FAIL_AFTER_RETIRE=1 run_signer >/dev/null 2>"$test_root/failhook.err"; then
	echo "phase 4 FAILED: test hook did not fail the run" >&2
	exit 1
fi
grep -q 'test hook: failing after retirement moves' "$test_root/failhook.err"
grep -q 'rollback: restored 1 retired APK(s)' "$test_root/failhook.err"
test -f "$gen_live/retireme-1-r2.apk"
test ! -e "$retired_dir/retireme-1-r2.apk"
# Retire the still-pending staged transaction (rename convention: it no
# longer ends in -ready), then heal with an empty staged set: the ledger
# must be exactly as before the failed run.
mv "$incoming/retireme-1-r4-fixture-ready" "$incoming/retireme-1-r4-fixture-retired-manual"
run_signer --full-audit >"$test_root/failhook-heal.out" 2>&1
grep -q 'ledger rows added: 0, removed: 0' "$test_root/failhook-heal.out"
[ "$(live_nvrs)" = "$(printf 'retireme-1-r2\nretireme-1-r3')" ]
echo "phase 4 ok: failed publish restored files, rows untouched"

# --- Phase 5: normal publish still works after the hook (trap state clean). ---
stage_fixture retireme 1-r4
run_signer >/dev/null
[ "$(live_nvrs)" = "$(printf 'retireme-1-r3\nretireme-1-r4')" ]
test -f "$retired_dir/retireme-1-r2.apk"
echo "phase 5 ok: ordinary publication unaffected"

# --- Phase 6: full audit explicitly lists added and removed rows. ---
rm -f "$gen_live/retireme-1-r4.apk"
run_signer --full-audit >"$test_root/audit.out" 2>&1
grep -q 'ledger rows added: 0, removed: 1' "$test_root/audit.out"
grep -q '^  - retireme-1-r4$' "$test_root/audit.out"
echo "phase 6 ok: heal lists removed rows"

# --- Phase 7: reap lists without approval, deletes only with it. ---
run_signer --reap-retired >"$test_root/reap-list.out" 2>&1 || true
grep -q 'retireme-1-r1.apk' "$test_root/reap-list.out"
test -f "$retired_dir/retireme-1-r1.apk"
run_signer --reap-retired --older-than 0 --approve-retired-removal >/dev/null
test ! -e "$retired_dir/retireme-1-r1.apk"
test ! -e "$retired_dir/retireme-1-r2.apk"
[ "$(live_nvrs | wc -l)" -eq 1 ]
test -f "$gen_live/retireme-1-r3.apk"
grep -q '"action":"reaped"' "$repo/retire-journal.jsonl"
echo "phase 7 ok: reap is explicit-only and live-safe"

# --- Final consistency: index, DB and disk agree via checkpkg path. ---
SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
SAPHIRA_REPO_DIR=$repo SAPHIRA_TRUST_KEY=$keys/test-repository.rsa.pub \
SAPHIRA_REPO_NAMES="genold genlive" \
	"$checkpkg" retireme >/dev/null

echo "retire-rollback: all phases passed"

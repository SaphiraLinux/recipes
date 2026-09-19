#!/bin/sh

# buildpkg cleanup-lifecycle tests: pre-build refusals leave no workspace,
# success purges stale siblings, failure caps stale history at one, and
# fail() never blesses a workspace it did not create.
#
# Part A is Transaction-level (fast, no namespaces). Part B drives main()
# end to end with a stub resolvepkg (needs user namespaces, like
# clean-build.sh).
#
# usage: buildpkg-lifecycle.sh BUILDPKG

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s BUILDPKG\n' "$0" >&2
	exit 1
}

buildpkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$buildpkg")/../.." && pwd)
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-lifecycle-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
build_root=$test_root/build
mkdir -p "$build_root"

cleanup()
{
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
	find "$test_root" -depth -delete 2>/dev/null || true
}
trap 'cleanup' EXIT HUP INT TERM

# --- Part A: Transaction-level lifecycle (no namespaces) --------------------
python3 - "$buildpkg" "$build_root" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import sys

spec = importlib.util.spec_from_loader(
    "buildpkg_under_test",
    importlib.machinery.SourceFileLoader("buildpkg_under_test", sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

build_root = pathlib.Path(sys.argv[2])
stub = build_root / "stub-bindir"
stub.mkdir()
(state := build_root / "rootfs_overlay" / "state").mkdir(parents=True)
receipt = b'{"schema":"saphira-package-seed/v1","resolved":[]}\n'
(state / "package-seed.json").write_bytes(receipt)
(state / "base.json").write_text(
    json.dumps({"fingerprint": "lifecycle-fixture"}) + "\n")


def config():
    return {"SAPHIRA_BUILD_ROOT": str(build_root),
            "SAPHIRA_ARCH": "x86_64",
            "SAPHIRA_BINDIR": str(stub)}


def stub_resolvepkg(message):
    tool = stub / "resolvepkg"
    quoted = "'" + message.replace("'", "'\\''") + "'"
    tool.write_text("#!/bin/sh\nprintf '%s\\n' " + quoted + " >&2\nexit 1\n")
    tool.chmod(0o755)


def transaction(target):
    return module.Transaction(config(), target, None)


# T1: published-NVR refusal carries the actual refusal and aborts clean.
refusal_nvr = ("resolvepkg: refusing to rebuild refused-1-r1: exact NVR "
               "already published in live repository 'hatched' - bump pkgrel")
stub_resolvepkg(refusal_nvr)
txn = transaction("refused")
txn.prepare()
try:
    txn.resolve()
except module.BuildError as exc:
    assert str(exc) == f"resolver refused refused: {refusal_nvr}", str(exc)
else:
    raise SystemExit("T1: resolve() did not refuse")
txn.abort_prebuild("resolver refused refused: x")
assert not (build_root / "refused.buildpkg").exists(), "T1: workspace retained"
assert list(build_root.glob("refused.buildpkg*")) == [], "T1: residue"

# T2: lineage refusal takes the same clean path.
refusal_lin = ("resolvepkg: generation lineage repair required: foo-1-r1 "
               "already exists in generation repository 'hatchling'")
stub_resolvepkg(refusal_lin)
txn = transaction("foo")
txn.prepare()
try:
    txn.resolve()
except module.BuildError as exc:
    assert str(exc) == f"resolver refused foo: {refusal_lin}", str(exc)
else:
    raise SystemExit("T2: resolve() did not refuse")
txn.abort_prebuild("refused")
assert not (build_root / "foo.buildpkg").exists(), "T2: workspace retained"

# T3: genuine failure retains FAILED + recovery notes.
txn = transaction("genuine")
txn.prepare()
txn.fail("boom")
ws = build_root / "genuine.buildpkg"
assert (ws / "FAILED").read_text() == module.FAILED_MARKER, "T3: no marker"
assert (ws / "OVERLAY-RECOVER.txt").is_file(), "T3: no recovery notes"

# T4: a second failure caps stale siblings at the newest ONE.
(oldest := ws.with_name("genuine.buildpkg.stale-20200101T000000Z")).mkdir()
(oldest / "FAILED").write_text(module.FAILED_MARKER)
(newer := ws.with_name("genuine.buildpkg.stale-20260101T000000Z")).mkdir()
(newer / "FAILED").write_text(module.FAILED_MARKER)
txn.fail("boom again")
remaining = sorted(build_root.glob("genuine.buildpkg.stale-*"))
assert [path.name for path in remaining] == [newer.name], \
    f"T4: stale not capped: {remaining}"
assert (ws / "FAILED").read_text() == module.FAILED_MARKER, "T4: plain lost"

# T5: success removes the plain workspace AND all stale siblings -
# including ones with a kernel-style mode-000 overlay workdir (host-side
# removal must restore owner access first, never die halfway).
txn = transaction("lucky")
txn.prepare()
s1 = build_root / "lucky.buildpkg.stale-20200101T000000Z"
(s1 / "work" / "work").mkdir(parents=True)
(s1 / "work" / "work" / "link").write_text("x\n")
(s1 / "artifacts").mkdir()
(s1 / "artifacts" / "lucky-1-r1.apk").write_text("x\n")
import os
os.chmod(s1 / "work" / "work", 0)
os.chmod(s1 / "work", 0)
s2 = build_root / "lucky.buildpkg.stale-20260101T000000Z"
s2.mkdir()
txn.succeed()
assert not (build_root / "lucky.buildpkg").exists(), "T5: plain retained"
assert list(build_root.glob("lucky.buildpkg.stale-*")) == [], "T5: stale left"

# T6: fail() never blesses a workspace it did not create (prepare-time
# collision with an unmarked directory).
alien = build_root / "alien.buildpkg"
alien.mkdir()
(alien / "sentinel").write_text("keep\n")
txn = transaction("alien")
try:
    txn.prepare()
except module.BuildError as exc:
    assert "without a trusted FAILED marker" in str(exc), str(exc)
else:
    raise SystemExit("T6: unmarked collision was not refused")
txn.fail("prepare never got there")
assert not (alien / "FAILED").exists(), "T6: unmarked workspace blessed"
assert (alien / "sentinel").read_text() == "keep\n", "T6: alien touched"

# T7: the canonical remover is fail-closed on identity.
try:
    module._remove_workspace_tree(build_root, pathlib.Path("/tmp/evil.buildpkg"))
except module.BuildError as exc:
    assert "refusing workspace" in str(exc), str(exc)
else:
    raise SystemExit("T7: outside-build-root removal was not refused")

print("Part A (Transaction-level lifecycle): OK")
PY

# --- Part B: main() end to end with a refusing stub resolver ---------------
repo_dir=$test_root/repo
mkdir -p "$repo_dir/testgen/x86_64" "$test_root/recipes" "$test_root/incoming"
: > "$repo_dir/testgen/x86_64/probe-seed-pkg-1-r1.apk"
stub_main=$test_root/main-bindir
mkdir -p "$stub_main"
cat > "$stub_main/resolvepkg" <<'STUB'
#!/bin/sh
printf '%s\n' "resolvepkg: refusing to rebuild refused-pkg-1-r1: exact NVR already published in live repository 'hatched' - bump pkgrel for a genuinely new revision" >&2
exit 1
STUB
chmod 755 "$stub_main/resolvepkg"

# Fabricate a fresh canonical base so ensure() passes without rebuilding:
# fingerprint pins (schema, arch, seed); intact() files; receipt resolving
# against the throwaway live repo; empty live listing would also pass.
seed_names='probe-seed-pkg'
fingerprint=$(python3 -c 'import hashlib; print(hashlib.sha256(b"saphira-base-root/v1\x00x86_64\x00probe-seed-pkg\x00").hexdigest())')
mkdir -p "$build_root/rootfs_overlay/base/bin" \
	"$build_root/rootfs_overlay/base/usr/bin" \
	"$build_root/rootfs_overlay/base/etc/ssl/certs" \
	"$build_root/rootfs_overlay/state"
ln -s bash "$build_root/rootfs_overlay/base/bin/sh"
: > "$build_root/rootfs_overlay/base/usr/bin/env"
: > "$build_root/rootfs_overlay/base/usr/bin/apk"
: > "$build_root/rootfs_overlay/base/etc/ssl/certs/ca-certificates.crt"
cat > "$build_root/rootfs_overlay/state/base.json" <<JSON
{"arch":"x86_64","created":"2026-01-01T00:00:00Z","fingerprint":"$fingerprint","schema":"saphira-base-root-state/v2","seed":"$seed_names"}
JSON
cat > "$build_root/rootfs_overlay/state/package-seed.json" <<'JSON'
{"generation":"Saphira-v0.2-package-seed","resolved":[{"arch":"x86_64","name":"probe-seed-pkg","version":"1-r1"}],"schema":"saphira-package-seed/v1","seed":["probe-seed-pkg"]}
JSON
: > "$test_root/trust-key"

run_main_buildpkg()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_RECIPE_ROOT=$test_root/recipes \
	SAPHIRA_BUILD_ROOT=$build_root \
	SAPHIRA_REPO_DIR=$repo_dir \
	SAPHIRA_REPO_NAMES=testgen \
	SAPHIRA_INCOMING_DIR=$test_root/incoming \
	SAPHIRA_BINDIR=$stub_main \
	SAPHIRA_PACKAGE_TMP=$test_root/package-tmp \
	SAPHIRA_HOST_RESOLV_CONF=/etc/resolv.conf SAPHIRA_HOST_HOSTS_FILE=/etc/hosts \
	SAPHIRA_BUILD_SEED=$seed_names \
	SAPHIRA_APK=/usr/bin/apk SAPHIRA_BWRAP=/usr/bin/bwrap \
	SAPHIRA_PYTHON=/usr/bin/python3 SAPHIRA_TRUST_KEY=$test_root/trust-key \
	SAPHIRA_ROOT_SHELL=/bin/bash SAPHIRA_SOURCE_DATE_EPOCH=1753401600 \
	SAPHIRA_ARCH=x86_64 \
		"$buildpkg" "$@"
}

# Published-NVR refusal through main(): exit nonzero, refusal printed, no
# workspace anywhere, no holder or mount left behind.
if run_main_buildpkg refused-pkg > "$test_root/refusal.out" 2> "$test_root/refusal.err"; then
	printf '%s\n' 'Part B: refusal unexpectedly succeeded' >&2
	exit 1
fi
grep 'resolver refused refused-pkg: resolvepkg: refusing to rebuild refused-pkg-1-r1' \
	"$test_root/refusal.err" >/dev/null
grep 'pre-build refusal; workspace removed, no diagnostic retained' \
	"$test_root/refusal.err" >/dev/null
test ! -e "$build_root/refused-pkg.buildpkg"
test -z "$(find "$build_root" -maxdepth 1 -name 'refused-pkg.buildpkg*' -print -quit)"
test -z "$(grep -rls "upperdir=$build_root/refused-pkg.buildpkg/upper" /proc/[0-9]*/mountinfo 2>/dev/null)"

printf '%s\n' 'buildpkg cleanup-lifecycle (refusal/success/failure-cap/no-bless) tests: OK'

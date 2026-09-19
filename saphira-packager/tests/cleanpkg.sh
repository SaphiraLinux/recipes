#!/bin/sh

# cleanpkg lifecycle tests: failed-workspace removal, holder handling,
# and refusal paths. Runs as the invoking user (no unshare, no root):
# passing here proves non-root operation directly.
#
# usage: cleanpkg.sh CLEANPKG

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s CLEANPKG\n' "$0" >&2
	exit 1
}

cleanpkg=$1
source_root=$(CDPATH= cd -- "$(dirname -- "$cleanpkg")/../.." && pwd)
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-cleanpkg-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'find "$test_root" -depth -delete' EXIT HUP INT TERM
build_root=$test_root/build
mkdir -p "$build_root"

run_cleanpkg()
{
	SAPHIRA_CONFIG_FILE=$source_root/saphira-packager/files/package_builder.sh \
	SAPHIRA_BUILD_ROOT=$build_root \
		"$cleanpkg" "$@"
}

mkWorkspace()
{
	ws=$build_root/$1.buildpkg
	mkdir -p "$ws"
	printf 'saphira-buildpkg-failed/v1' > "$ws/FAILED"
}

# A holder pid that vanished (or was never valid) must be silent: no
# "/proc/<pid>/cmdline: No such file or directory" on stderr, workspace
# still removed. pid_max+1 can never be assigned, so it is
# deterministically dead.
mkWorkspace vanished
deadpid=$(($(cat /proc/sys/kernel/pid_max) + 1))
printf '{"pid":%s}\n' "$deadpid" > "$build_root/vanished.buildpkg/overlay-holder.json"
run_cleanpkg vanished > "$test_root/vanished.out" 2> "$test_root/vanished.err"
test ! -e "$build_root/vanished.buildpkg"
test ! -s "$test_root/vanished.err"

# A live pid whose cmdline is not the holder is a mismatch, never a
# kill: our own shell qualifies and is safe by construction.
mkWorkspace mismatch
printf '{"pid":%s}\n' "$$" > "$build_root/mismatch.buildpkg/overlay-holder.json"
run_cleanpkg mismatch > "$test_root/mismatch.out" 2> "$test_root/mismatch.err"
test ! -e "$build_root/mismatch.buildpkg"

# Malformed holder records are skipped, not fatal.
mkWorkspace malformed
printf '{"pid":"abc"}\n' > "$build_root/malformed.buildpkg/overlay-holder.json"
run_cleanpkg malformed >/dev/null 2>&1
test ! -e "$build_root/malformed.buildpkg"

# Unmarked workspaces are refused and kept.
mkdir -p "$build_root/unmarked.buildpkg"
if run_cleanpkg unmarked > "$test_root/unmarked.out" 2> "$test_root/unmarked.err"; then
	printf '%s\n' 'unmarked workspace unexpectedly removed' >&2
	exit 1
fi
grep 'refusing unmarked workspace' "$test_root/unmarked.err" >/dev/null
test -d "$build_root/unmarked.buildpkg"

# --unmarked refuses a marked FAILED workspace (default path owns those).
mkWorkspace marked
if run_cleanpkg --unmarked marked > "$test_root/marked.out" 2> "$test_root/marked.err"; then
	printf '%s\n' '--unmarked unexpectedly took a marked workspace' >&2
	exit 1
fi
grep 'use plain cleanpkg without --unmarked' "$test_root/marked.err" >/dev/null
test -d "$build_root/marked.buildpkg"

# --unmarked removes a dead unmarked workspace, fixing workdir-style
# owner-only permissions on the way (mode 000 subdir stands in for the
# overlay workdir's internal directory).
mkdir -p "$build_root/deadunmarked.buildpkg/work/work"
chmod 000 "$build_root/deadunmarked.buildpkg/work/work"
printf '{"pid":%s}\n' "$deadpid" > "$build_root/deadunmarked.buildpkg/overlay-holder.json"
run_cleanpkg --unmarked deadunmarked > "$test_root/deadunmarked.out" 2> "$test_root/deadunmarked.err"
grep 'removed unmarked workspace' "$test_root/deadunmarked.out" >/dev/null
test ! -e "$build_root/deadunmarked.buildpkg"

# --unmarked refuses a live workspace: a recorded holder whose cmdline
# still carries the holder marker for exactly this workspace. The fake
# holder is a sleeper whose argv[0] is the marker (never a real mount).
mkdir -p "$build_root/liveunmarked.buildpkg"
bash -c 'exec -a "$0" sleep 60' \
	"saphira-overlay-holder $build_root/liveunmarked.buildpkg" &
liveholder=$!
printf '{"pid":%s}\n' "$liveholder" > "$build_root/liveunmarked.buildpkg/overlay-holder.json"
sleep 0.5
if run_cleanpkg --unmarked liveunmarked > "$test_root/liveunmarked.out" 2> "$test_root/liveunmarked.err"; then
	kill "$liveholder" 2>/dev/null || true
	printf '%s\n' '--unmarked unexpectedly removed a live workspace' >&2
	exit 1
fi
grep 'appears live' "$test_root/liveunmarked.err" >/dev/null
test -d "$build_root/liveunmarked.buildpkg"
kill "$liveholder" 2>/dev/null || true
wait "$liveholder" 2>/dev/null || true
rm -rf "$build_root/liveunmarked.buildpkg"

printf '%s\n' 'cleanpkg removal, holder-race silence, and refusal tests: OK'

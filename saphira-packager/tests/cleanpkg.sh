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
test_root=$(mktemp -d /tmp/saphira-cleanpkg-test.XXXXXX)
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

printf '%s\n' 'cleanpkg removal, holder-race silence, and refusal tests: OK'

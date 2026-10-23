#!/bin/sh

# openrc binfmt writer contract: fragment registration must use
# printf '%s' (single write), never echo.
#
# Root cause it locks in (SEV boot defect 2026-10-23, proven by strace):
# bash echo emits the trailing newline as a separate writev segment and
# the kernel invokes .write once per segment; the lone-newline retry is
# rejected with EINVAL even though the operation already succeeded on the
# first segment. Every fragment therefore printed a spurious "invalid
# entry" failure at every boot while every registration actually worked.
# printf '%s' emits no newline: one write, whole success, silence.
#
# usage: binfmt-writer.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

failures=0
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }
ok() { printf 'ok       %s\n' "$*"; }

patch=$source_root/openrc/files/saphira-binfmt-paths.patch
[ -f "$patch" ] || { bad 'binfmt paths patch missing'; exit 1; }

# The printf writer must be present (unregister + register).
grep -Fq "printf '%s' '-1'" "$patch" ||
	bad 'patch lacks the printf unregister write'
grep -Fq '${line}" > /proc/sys/fs/binfmt_misc/register' "$patch" ||
	bad 'patch lacks the printf register write'

# No added code line may write via echo: an echo write rediscovers the
# split-newline EINVAL. (Comment lines mentioning echo are fine.)
echo_writes=$(grep '^+' "$patch" | grep -v '^+++' | grep -vE '^\+\s*#' | grep -E '(^|[[:space:]])echo[[:space:]]' || true)
[ -z "$echo_writes" ] ||
	bad "patch adds echo writes (must be printf): $echo_writes"

# The diagnostic-path fix rides in the same patch (no doubled slashes).
grep -Fq "binfmt_dirs='/usr/lib/binfmt.d /run/binfmt.d /etc/binfmt.d'" "$patch" ||
	bad 'patch lost the doubled-slash diagnostic fix'

# The patch must still apply to the vendored sources.
if command -v patch >/dev/null 2>&1; then
	work=${SAPHIRA_TMPDIR:-/build/tmp}/binfmt-writer-$$
	mkdir -p "$work" || { bad 'cannot create scratch'; exit 1; }
	trap 'rm -rf -- "$work"' EXIT HUP INT TERM
	tar -xzf "$source_root/openrc/files/0.62.1.tar.gz" -C "$work" openrc-0.62.1/sh/binfmt.sh.in ||
		{ bad 'cannot extract pristine binfmt.sh.in'; exit 1; }
	patch --dry-run -s -Np1 -d "$work/openrc-0.62.1" -i "$patch" >/dev/null 2>&1 ||
		bad 'binfmt paths patch does not apply to vendored 0.62.1'
	ok 'binfmt paths patch applies to vendored 0.62.1'
else
	printf 'binfmt-writer: patch(1) unavailable, apply check skipped\n' >&2
fi

if [ "$failures" -gt 0 ]; then
	printf 'binfmt-writer: %d failure(s)\n' "$failures" >&2
	exit 1
fi
ok 'binfmt writer contract holds (printf writes, no echo, clean paths)'

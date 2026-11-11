#!/bin/bash
# Guards the tool-scratch contract proven broken on Minimer 2026-11-08:
# install-to-disk died with
#   mktemp: failed to create file via template
#   '/build/tmp/saphira-plan.XXXXXX': No such file or directory
# because the plan buffer used the raw ${SAPHIRA_TMPDIR:-/build/tmp}
# default, and installed machines have no /build tree.
#
# Contract (same as saphira-earlyfw's stage_base since r5): scratch
# prefers SAPHIRA_TMPDIR, falls back to host /tmp only when that names
# no usable directory - never invent /build on a machine that does not
# have one, never fail merely because the preferred root is absent.
# All mktemp templates in the tool must therefore derive from
# $(saphira_tmpdir), never from a hardcoded path.
#
# Asserted against the recipe source plus a live unit test of the
# extracted helper (pure function, no side effects), rootless, with
# no build and no image assembly.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/.." && pwd)
image=$root/files/saphira-image

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf '%s\n' '# no hardcoded scratch paths in mktemp templates'

# Every mktemp template must come from a computed base ($tmpbase or
# $(saphira_tmpdir)), never from a literal directory. Comments name
# the old failure for the record and cannot match - they hold no
# mktemp invocation.
if /usr/bin/grep -n 'mktemp' "$image" | /usr/bin/grep -v '^[0-9]*:[[:space:]]*#' | /usr/bin/grep -v 'tmpbase\|saphira_tmpdir'; then
	bad 'mktemp template with a hardcoded path (use $tmpbase or $(saphira_tmpdir))'
else
	ok 'all mktemp templates derive from the computed scratch base'
fi

printf '%s\n' '# saphira_tmpdir falls back to /tmp'

helper=$(/usr/bin/sed -n '/^saphira_tmpdir()$/,/^}$/p' "$image")
if [ -z "$helper" ]; then
	bad 'cannot extract saphira_tmpdir from the tool'
elif ! printf '%s\n' "$helper" | /usr/bin/grep -q '\[ -d "\$base" \] || base=/tmp'; then
	bad 'saphira_tmpdir has no unusable-directory fallback to /tmp'
else
	ok 'saphira_tmpdir falls back to /tmp when the preferred root is absent'
fi

printf '%s\n' '# the fallback works live'

work=$(mktemp -d "${SAPHIRA_TMPDIR:-/build/tmp}/saphira-tmpdir-test.XXXXXX" 2>/dev/null || mktemp -d /tmp/saphira-tmpdir-test.XXXXXX) ||
	{ bad 'cannot create a test workspace'; work=; }
if [ -n "${work:-}" ]; then
	trap 'rm -rf -- "$work"' EXIT HUP INT TERM
	printf '%s\n' "$helper" > "$work/func.sh"
	# Preferred root present: returned as-is.
	got=$(SAPHIRA_TMPDIR="$work" sh -c '. "$1"; saphira_tmpdir' sh "$work/func.sh")
	if [ "$got" = "$work" ]; then
		ok 'usable SAPHIRA_TMPDIR is returned unchanged'
	else
		bad "usable SAPHIRA_TMPDIR not honoured (got '$got')"
	fi
	# Preferred root absent: /tmp, never an invented /build.
	got=$(SAPHIRA_TMPDIR="$work/no-such-dir" sh -c '. "$1"; saphira_tmpdir' sh "$work/func.sh")
	if [ "$got" = /tmp ]; then
		ok 'absent SAPHIRA_TMPDIR falls back to /tmp'
	else
		bad "absent SAPHIRA_TMPDIR did not fall back to /tmp (got '$got')"
	fi
	# Unset default on a machine without /build/tmp: /tmp as well.
	if [ -d /build/tmp ]; then
		ok '/build/tmp exists here: unset-default path covered by the cases above'
	else
		got=$(env -u SAPHIRA_TMPDIR sh -c '. "$1"; saphira_tmpdir' sh "$work/func.sh")
		if [ "$got" = /tmp ]; then
			ok 'unset default without /build falls back to /tmp'
		else
			bad "unset default without /build did not fall back (got '$got')"
		fi
	fi
	rm -rf -- "$work"
	trap - EXIT HUP INT TERM
fi

if [ "$failures" -gt 0 ]; then
	printf 'tmpdir-fallback: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'tmpdir-fallback: OK'

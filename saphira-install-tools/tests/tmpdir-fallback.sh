#!/bin/bash
# Guards the installer scratch contract proven broken on Minimer
# 2026-11-08: install-to-disk died with
#   mktemp: failed to create file via template
#   '/build/tmp/saphira-bootstrap.packages.XXXXXX': No such file or
#   directory
# because the helpers used the raw ${SAPHIRA_TMPDIR:-/build/tmp}
# default, and installed machines have no /build tree.
#
# Contract (same as saphira-earlyfw's stage_base since r5, and
# saphira-image since r43): scratch prefers SAPHIRA_TMPDIR and falls
# back to host /tmp only when that names no usable directory - never
# invent /build on a machine that does not have one, never fail
# merely because the preferred scratch root is absent.
#
# Asserted per tool (saphira-bootstrap, saphira-assemble-rootfs,
# saphira-genfstab): the helper carries the fallback, every mktemp
# template derives from it, and the extracted helper behaves live.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
files=$here/../files

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

for tool in saphira-bootstrap saphira-assemble-rootfs saphira-genfstab; do
	printf '%s\n' "# $tool scratch root"

	path=$files/$tool
	# Every mktemp template must derive from the helper - a literal
	# directory means a machine without it dies exactly like Minimer.
	if /usr/bin/grep -n 'mktemp' "$path" | /usr/bin/grep -v '^[0-9]*:[[:space:]]*#' | /usr/bin/grep -v 'saphira_tmpdir'; then
		bad "$tool: mktemp template bypasses saphira_tmpdir"
	else
		ok "$tool: all mktemp templates derive from saphira_tmpdir"
	fi

	helper=$(/usr/bin/sed -n '/^saphira_tmpdir()$/,/^}$/p' "$path")
	if [ -z "$helper" ]; then
		bad "$tool: cannot extract saphira_tmpdir"; continue
	fi
	if ! printf '%s\n' "$helper" | /usr/bin/grep -q '\[ -d "\$base" \] || base=/tmp'; then
		bad "$tool: saphira_tmpdir has no unusable-directory fallback to /tmp"
		continue
	fi
	ok "$tool: saphira_tmpdir falls back to /tmp when the preferred root is absent"

	# Live behaviour of the extracted helper (pure function, no side
	# effects): preferred root honoured, absent root falls back.
	work=$(mktemp -d "${SAPHIRA_TMPDIR:-/build/tmp}/saphira-installer-test.XXXXXX" 2>/dev/null || mktemp -d /tmp/saphira-installer-test.XXXXXX) ||
		{ bad "$tool: cannot create a test workspace"; continue; }
	printf '%s\n' "$helper" > "$work/func.sh"
	got=$(SAPHIRA_TMPDIR="$work" sh -c '. "$1"; saphira_tmpdir' sh "$work/func.sh")
	[ "$got" = "$work" ] ||
		{ bad "$tool: usable SAPHIRA_TMPDIR not honoured (got '$got')"; rm -rf -- "$work"; continue; }
	ok "$tool: usable SAPHIRA_TMPDIR is returned unchanged"
	got=$(SAPHIRA_TMPDIR="$work/no-such-dir" sh -c '. "$1"; saphira_tmpdir' sh "$work/func.sh")
	[ "$got" = /tmp ] ||
		bad "$tool: absent SAPHIRA_TMPDIR did not fall back to /tmp (got '$got')"
	[ "$got" = /tmp ] &&
		ok "$tool: absent SAPHIRA_TMPDIR falls back to /tmp"
	rm -rf -- "$work"
done

if [ "$failures" -gt 0 ]; then
	printf 'tmpdir-fallback: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'tmpdir-fallback: OK'

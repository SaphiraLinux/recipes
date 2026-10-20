#!/bin/sh
# check-boot-image-names.sh - kernel /boot image naming policy gate.
#
# Sourced by the saphira-kernel-<kver> recipe_install() after the /boot
# payload is staged, and runnable by hand against any live root
# (check_boot_image_names / PATH KVER). Pure path logic over explicit
# arguments (no builder globals), so the policy is unit-testable
# without building a kernel.
#
# Policy: kernel version, build revision, APK revision and the /boot
# image name are separate concepts. The image name carries ONLY the
# kernel version: vmlinuz-<kver>-akadata (likewise the System.map and
# config companions). No revision, no pkgrel, no counter, no baker's
# suffix, ever. A name like vmlinuz-7.1.5-akadata-1 is not "the same
# kernel with a revision marker": it is an unnamed artefact no tool
# can attribute, and grub will offer it as a separate boot entry for
# the same kernel version. Installation collisions are refused by apk
# (exact-path ownership); they are NEVER solved by renaming. This gate
# reports offenders and fails; it never deletes, renames or replaces
# anything (boot artefacts are removed only by explicit operator
# approval, never by tooling).
#
# Defensive shell: every failure prints `boot-image-names: ...` and
# the entry point returns non-zero (callers run under `set -eu`).

bin_die()
{
	printf 'boot-image-names: %s\n' "$*" >&2
	return 1
}

# check_boot_image_names ROOT KVER [KVER...] - assert every
# vmlinuz/System.map/config entry under ROOT/boot is exactly
# <prefix>-<kver>-akadata for one of the given kvers (several lines
# may be co-installed; each keeps its exact name). Reports all
# offenders, then returns non-zero.
check_boot_image_names()
{
	[ "$#" -ge 2 ] || { bin_die "usage: check_boot_image_names ROOT KVER [KVER...]"; return 1; }
	[ -d "$1/boot" ] || { bin_die "no boot dir at $1/boot"; return 1; }
	root=$1
	shift
	fails=0
	for prefix in vmlinuz System.map config; do
		for path in "$root/boot/$prefix"-*; do
			[ -e "$path" ] || continue
			name=${path##*/}
			matched=0
			for k in "$@"; do
				if [ "$name" = "$prefix-$k-akadata" ]; then
					matched=1
					break
				fi
			done
			if [ "$matched" -ne 1 ]; then
				printf 'boot-image-names: %s: unexpected %s payload name: %s (want exactly %s; revisions live in the APK NVR, never in the filename)\n' \
					"$root" "$prefix" "$name" "$prefix-<kver>-akadata" >&2
				fails=$((fails + 1))
			fi
		done
	done
	# Bare vmlinuz without a version stem is equally unnamed.
	if [ -e "$root/boot/vmlinuz" ]; then
		printf 'boot-image-names: %s: bare unversioned vmlinuz (never emitted by packaging)\n' \
			"$root" >&2
		fails=$((fails + 1))
	fi
	if [ "$fails" -ne 0 ]; then
		bin_die "$root: $fails unexpected /boot name(s) (see above)"
		return 1
	fi
	printf 'boot-image-names: %s: /boot names exact (kvers: %s)\n' "$root" "$*"
}

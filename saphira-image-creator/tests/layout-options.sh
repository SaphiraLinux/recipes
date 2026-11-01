#!/bin/bash
# --boot-size (ext4), --swap-size and --earlyfw: optional layout
# features with safe defaults.
#
# Defaults are historical: no separate /boot on ext4 without an
# explicit --boot-size, no swap partition without --swap-size, no
# early-firmware images without --earlyfw. A missing flag must never
# change the emitted plan, and an explicit flag must reshape it
# exactly (contiguous partitions, swap last, refusals fail closed
# with a non-zero exit).
#
# Early firmware is strictly opt-in: generation runs only with the
# flag, and later hook refreshes only on machines carrying the
# opt-in marker. Mere presence of saphira-earlyfw in the target
# must never trigger generation.
#
# Everything here runs through `plan` (static: no image is built,
# no privileged operation, no loop device) plus source assertions
# in the clean-image-guards.sh style for the parts plan cannot
# reach (the --earlyfw gate lives in generate_earlyfw, not the
# partitioner).

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
tool=${SAPHIRA_IMAGE:-$here/../files/saphira-image}

test -x "$tool" || {
	printf 'saphira-image is not executable: %s\n' "$tool" >&2
	exit 1
}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

plan_names()
{
	# Partition names in plan order for: tool plan <args...>
	"$tool" plan "$@" 2>"$work/err" | /usr/bin/grep '^start=' |
		/usr/bin/sed -n 's/.*name="\([^"]*\)".*/\1/p' || true
}

plan_ok()
{
	# plan_ok <desc> <expected-names...> -- <plan args...>: the plan
	# succeeds and emits exactly the expected partition names.
	desc=$1; shift
	expected=$1; shift
	# shellcheck disable=SC2086
	names=$(plan_names "$@")
	if [ "$names" = "$expected" ]; then
		ok "$desc"
	else
		bad "$desc: got [$names], want [$expected]"
	fi
}

plan_refused()
{
	# plan_refused <desc> -- <plan args...>: the plan dies non-zero.
	desc=$1; shift
	if "$tool" plan "$@" >/dev/null 2>&1; then
		bad "$desc: plan succeeded, expected refusal"
	else
		ok "$desc"
	fi
}

printf '%s\n' '# defaults are historical: no boot, no swap partitions'

plan_ok 'uefi default is esp+root' \
	$'esp\nroot' --target uefi-systemd --size 2G
plan_ok 'bios default is bios-boot+root' \
	$'bios-boot\nroot' --target bios-openrc --size 2G

printf '%s\n' '# explicit --boot-size partitions a separate /boot on ext4'

plan_ok 'uefi +boot-size gains boot between esp and root' \
	$'esp\nboot\nroot' --target uefi-systemd --size 2G --boot-size 128
plan_ok 'bios +boot-size gains boot between bios-boot and root' \
	$'bios-boot\nboot\nroot' --target bios-openrc --size 2G --boot-size 128

printf '%s\n' '# explicit --swap-size appends swap last'

plan_ok 'uefi +swap appends swap after root' \
	$'esp\nroot\nswap' --target uefi-systemd --size 2G --swap-size 512M
plan_ok 'uefi +boot +swap orders esp,boot,root,swap' \
	$'esp\nboot\nroot\nswap' --target uefi-systemd --size 4G --boot-size 128 --swap-size 512M

printf '%s\n' '# the swap line carries the sfdisk-writable type GUID'

# sfdisk 2.41.1 fails to write the retired DPS swap GUID outright
# ("Failed to add #N partition: Invalid argument" at add time,
# "failed to set partition type" via --part-type; proven file-backed
# on identical geometry while ESP/Linux/home/random GUIDs all apply
# cleanly). Its `swap` alias canonicalizes to the GUID asserted
# here, so the plan must emit exactly these bytes.
plan_swap_type()
{
	# Swap type GUID from: tool plan <args...>
	"$tool" plan "$@" 2>"$work/err" |
		/usr/bin/sed -n 's/^start=.* type=\([^,]*\), name="swap".*/\1/p' || true
}

swap_type=$(plan_swap_type --target uefi-systemd --size 4G --boot-size 128 --swap-size 512M)
if [ "$swap_type" = '0657FD6D-A4AB-43C4-84E5-0933C84B4F4F' ]; then
	ok 'swap line carries the canonical sfdisk-writable GUID'
else
	bad "swap line carries [$swap_type], want the canonical GUID sfdisk accepts"
fi

printf '%s\n' '# the emitted 4-part plan applies cleanly through sfdisk'

# Round-trip the exact plan through sfdisk onto a sparse file (no
# device, no privileges, no loop mount): a plan that sfdisk cannot
# apply is a plan that install-to-disk cannot use. This is the test
# that would have caught the retired swap GUID before it reached
# hardware.
if command -v sfdisk >/dev/null 2>&1 && command -v truncate >/dev/null 2>&1; then
	img=$work/disk.img
	truncate -s 4G "$img" || bad 'cannot create scratch image'
	if "$tool" plan --target uefi-systemd --size 2G --boot-size 128 --swap-size 512M >"$work/swap.sfdisk" 2>"$work/plan.err"; then
		if sfdisk --label gpt "$img" <"$work/swap.sfdisk" >"$work/sfdisk.out" 2>&1; then
			dump=$(sfdisk -d "$img" 2>/dev/null)
			nparts=$(printf '%s\n' "$dump" | /usr/bin/grep -c '^/') || nparts=0
			swapline=$(printf '%s\n' "$dump" | /usr/bin/grep -i 'name="swap"' || true)
			if [ "$nparts" = 4 ] && printf '%s\n' "$swapline" | /usr/bin/grep -q '0657FD6D-A4AB-43C4-84E5-0933C84B4F4F'; then
				ok 'esp+boot+root+swap plan applies with swap typed'
			else
				bad "sfdisk round-trip wrong: [$nparts parts] [$swapline]"
			fi
		else
			bad "sfdisk rejected the emitted plan: $(tail -n 3 "$work/sfdisk.out")"
		fi
	else
		bad "plan for the round-trip failed: $(cat "$work/plan.err")"
	fi
else
	ok 'sfdisk replay skipped (sfdisk or truncate not installed)'
fi

printf '%s\n' '# impossible layouts refuse instead of emitting garbage'

plan_refused 'over-budget boot+swap refused' \
	--target uefi-systemd --size 512M --boot-size 256 --swap-size 256M
plan_refused 'unaligned swap refused' \
	--target uefi-systemd --size 2G --swap-size 1000K
plan_refused 'tiny swap refused' \
	--target uefi-systemd --size 2G --swap-size 1M

printf '%s\n' '# early firmware is opt-in, never presence-triggered'

if /usr/bin/grep -q -- '--earlyfw' "$here/../files/saphira-image"; then
	ok '--earlyfw flag exists'
else
	bad '--earlyfw flag missing from usage/parsing'
fi
if /usr/bin/grep -q 'EARLYFW:-0' "$here/../files/saphira-image" &&
	/usr/bin/grep -q 'earlyfw-enabled' "$here/../files/saphira-image"; then
	ok 'generation gated on the flag with a persistent opt-in marker'
else
	bad 'earlyfw gate or marker missing'
fi

if [ "$failures" -ne 0 ]; then
	printf 'layout-options: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'layout-options tests: OK'

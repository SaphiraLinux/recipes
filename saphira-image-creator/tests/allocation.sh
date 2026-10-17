#!/bin/bash
# --size and --allocate are two independent controls.
#
# --size is the CAPACITY of the image or device. --allocate is how much
# of that capacity the initial partition layout occupies; the rest stays
# unallocated for later growth. A 128G qcow2 with --allocate 10% is a
# 128G virtual disk whose partitions cover about 12.8G, which is thin
# provisioning done properly rather than a small disk with a big name.
#
# The two were easy to conflate because the original single option grew
# the partitions to fill the whole image. Keeping them separate is what
# makes a VM template useful: the guest sees the full capacity and the
# root filesystem can be grown later without the disk being resized.
#
# Everything here runs through `plan`, which is static: no image is
# built, no privileged operation, no loop device.

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

plan()
{
	"$tool" plan --target "$1" --size "$2" "${@:3}" 2>&1
}

# The last partition's end sector, which is what decides how much of the
# device the layout actually claims.
last_end()
{
	/usr/bin/grep '^start=' "$1" |
		/usr/bin/sed -n 's/^start=\([0-9]*\), size=\([0-9]*\).*/\1 \2/p' |
		/usr/bin/awk '{ end = $1 + $2; last = end } END { print last }'
}

part_size()
{
	/usr/bin/grep '^start=' "$1" | /usr/bin/tail -1 |
		/usr/bin/sed -n 's/^start=[0-9]*, size=\([0-9]*\).*/\1/p'
}

printf '%s\n' '--allocate 100% reproduces the historical layout exactly'

# This is the compatibility guarantee. The single --size option grew the
# partitions to fill the image, so "allocate everything" must be the
# same plan as omitting the option entirely, byte for byte.
plan uefi-saphira 128G --allocate 100% > "$work/p100" 2>&1
plan uefi-saphira 128G > "$work/pall" 2>&1
if /usr/bin/grep '^start=' "$work/p100" > "$work/a" &&
	/usr/bin/grep '^start=' "$work/pall" > "$work/b" &&
	cmp -s "$work/a" "$work/b"; then
	ok 'allocate 100% is identical to omitting --allocate'
else
	bad 'allocate 100% changed the historical layout'
	rtk diff "$work/b" "$work/a" 2>/dev/null || true
fi

printf '%s\n' 'a percentage partitions only part of the capacity'

plan uefi-saphira 128G --allocate 10% > "$work/p10" 2>&1
if /usr/bin/grep -q 'allocate=10%' "$work/p10"; then
	ok 'the plan records the allocation'
else
	bad 'the plan does not report the allocation'
fi

# 10% of 128G is about 12.8G. The partitions must END near there, not
# near the end of the device: that gap is the whole feature.
end=$(last_end "$work/p10")
total_sectors=$((128 * 1024 * 1024 * 1024 / 512))
ten_pct=$((total_sectors / 10))
if [ -n "$end" ] && [ "$end" -lt $((ten_pct + 65536)) ] &&
	[ "$end" -gt $((ten_pct - 65536)) ]; then
	ok "the layout ends near 10% of the device (sector $end of $total_sectors)"
else
	bad "expected the layout to end near sector $ten_pct, got '$end' of $total_sectors"
fi

# And the remainder must genuinely be unallocated, not merely unused.
if [ "$end" -lt $((total_sectors / 2)) ]; then
	ok 'most of the device is left unallocated for later growth'
else
	bad 'the layout consumed the device despite allocating 10%'
fi

printf '%s\n' 'the alignment gap and the GPT tail are honoured'

# The first partition starts at sector 2048 (1 MiB), not 0.
first=$(/usr/bin/grep '^start=' "$work/p10" | /usr/bin/head -1 |
	/usr/bin/sed -n 's/^start=\([0-9]*\).*/\1/p')
if [ "$first" = 2048 ]; then
	ok 'the first partition starts at the 1 MiB alignment boundary'
else
	bad "the first partition starts at sector $first, expected 2048"
fi

# The backup GPT header lives in the final sectors of the DEVICE, not of
# the budget, so a partial allocation must still stop short of the end.
if [ "$end" -le $((total_sectors - 2048)) ]; then
	ok 'the layout leaves the GPT tail reserve inside the device'
else
	bad "the layout runs into the GPT tail reserve (ends at $end of $total_sectors)"
fi

printf '%s\n' 'an absolute allocation behaves the same way'

plan uefi-saphira 128G --allocate 40G > "$work/p40" 2>&1
end40=$(last_end "$work/p40")
if [ -n "$end40" ] && [ "$end40" -lt $((total_sectors / 2)) ]; then
	ok "an absolute --allocate 40G also leaves room (ends at sector $end40)"
else
	bad "an absolute --allocate 40G did not leave room (end '$end40')"
fi

# The ESP is subtracted from the allocation, not added to it: allocating
# 40G means the partitions TOGETHER cover 40G.
esp=$(/usr/bin/grep '^start=' "$work/p40" | /usr/bin/head -1 |
	/usr/bin/sed -n 's/^start=[0-9]*, size=\([0-9]*\).*/\1/p')
root=$(part_size "$work/p40")
budget=$((40 * 1024 * 1024 * 1024 / 512))
if [ $((esp + root)) -le "$budget" ]; then
	ok 'the ESP is inside the allocation rather than added on top'
else
	bad "the ESP+root ($((esp + root)) sectors) exceeds the 40G budget ($budget)"
fi

printf '%s\n' 'nonsense and impossible allocations are refused'

for bad_alloc in '40G:8G' ; do
	alloc=${bad_alloc%:*}
	size=${bad_alloc#*:}
	if plan uefi-saphira "$size" --allocate "$alloc" > "$work/x" 2>&1; then
		bad "--allocate $alloc must not fit in --size $size"
	else
		ok "--allocate $alloc is refused for --size $size"
	fi
done

for value in '101%' '0%' 'banana' '10X' '%'; do
	if plan uefi-saphira 128G --allocate "$value" > "$work/x" 2>&1; then
		bad "--allocate '$value' must be refused"
	else
		ok "--allocate '$value' is refused"
	fi
done

printf '%s\n' 'the BIOS layout honours it too'

plan bios-saphira 128G --allocate 10% > "$work/pbio" 2>&1
if /usr/bin/grep -q 'bios-boot' "$work/pbio" && /usr/bin/grep -q 'name="root"' "$work/pbio"; then
	ok 'the BIOS layout keeps its bios-boot partition under an allocation'
else
	bad 'the BIOS layout lost its bios-boot partition under an allocation'
fi

if test "$failures" -ne 0; then
	printf 'allocation: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'allocation: OK'
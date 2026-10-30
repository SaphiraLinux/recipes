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
	# tail lives in /bin (coreutils --bindir), not /usr/bin: the old
	# /usr/bin/tail spelling failed on every Saphira host while the
	# checks using it silently mis-compared empty values.
	/usr/bin/grep '^start=' "$1" | /bin/tail -1 |
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

printf '%s\n' 'the hybrid USB layout carries all three partitions in order'

plan usb-installer 8G > "$work/phyb" 2>&1
if /usr/bin/grep -q 'name="bios-boot"' "$work/phyb" && /usr/bin/grep -q 'name="esp"' "$work/phyb" && /usr/bin/grep -q 'name="root"' "$work/phyb"; then
	ok 'the hybrid layout has bios-boot, ESP and root'
else
	bad 'the hybrid layout is missing a partition'
fi
if /usr/bin/awk '/^start=/{print}' "$work/phyb" | /usr/bin/grep -q .; then
	names=$(/usr/bin/grep -o 'name="[^"]*"' "$work/phyb" | /usr/bin/awk '{ printf "%s ", $0 } END { print "" }')
	test "$names" = 'name="bios-boot" name="esp" name="root" ' && ok 'hybrid partitions are ordered bios-boot, ESP, root' || bad "hybrid partitions misordered: $names"
fi

printf '%s\n' '--esp-size selects from the restricted ladder'

plan uefi-saphira 128G --esp-size 512 > "$work/esp512" 2>&1
esp512=$(/usr/bin/grep '^start=' "$work/esp512" | /usr/bin/head -1 |
	/usr/bin/sed -n 's/^start=[0-9]*, size=\([0-9]*\).*/\1/p')
if [ "$esp512" = 1048576 ]; then
	ok 'a 512MiB ESP occupies 1048576 sectors'
else
	bad "expected a 1048576-sector ESP, got '$esp512'"
fi
if /usr/bin/grep -q 'esp=512MiB' "$work/esp512"; then
	ok 'the plan records the ESP size'
else
	bad 'the plan does not report the ESP size'
fi

# Hybrid carries the same ESP one slot over.
plan usb-installer 8G --esp-size 256 > "$work/hyb256" 2>&1
esp256=$(/usr/bin/grep '^start=' "$work/hyb256" | /usr/bin/sed -n '2p' |
	/usr/bin/sed -n 's/^start=[0-9]*, size=\([0-9]*\).*/\1/p')
if [ "$esp256" = 524288 ]; then
	ok 'a hybrid 256MiB ESP occupies 524288 sectors'
else
	bad "expected a 524288-sector hybrid ESP, got '$esp256'"
fi

for esp_bad in 8 32 33 63 0 banana 513 1025; do
	if plan uefi-saphira 128G --esp-size "$esp_bad" > "$work/x" 2>&1; then
		bad "--esp-size '$esp_bad' must be refused"
	else
		ok "--esp-size '$esp_bad' is refused"
	fi
done

printf '%s\n' '--root-size names an exact root and leaves the rest'

plan uefi-saphira 128G --root-size 20G > "$work/root20" 2>&1
root20=$(part_size "$work/root20")
if [ "$root20" = 41943040 ]; then
	ok 'a 20GiB root occupies exactly 41943040 sectors'
else
	bad "expected a 41943040-sector root, got '$root20'"
fi
# ESP + root must end well short of the device: the remainder is
# unallocated, never back-filled.
end20=$(last_end "$work/root20")
if [ -n "$end20" ] && [ "$end20" -lt $((total_sectors / 2)) ]; then
	ok "an exact root leaves the remainder unallocated (ends at sector $end20)"
else
	bad "an exact root consumed the device (end '$end20')"
fi
if /usr/bin/grep -q 'root=20G' "$work/root20"; then
	ok 'the plan records the root size'
else
	bad 'the plan does not report the root size'
fi

printf '%s\n' '--root-size works on every layout'

plan bios-saphira 128G --root-size 20G > "$work/broot20" 2>&1
if [ "$(part_size "$work/broot20")" = 41943040 ] && /usr/bin/grep -q 'name="bios-boot"' "$work/broot20"; then
	ok 'a BIOS exact root keeps its bios-boot partition'
else
	bad 'a BIOS exact root is wrong'
fi
plan usb-installer 8G --root-size 1G > "$work/hroot1" 2>&1
if [ "$(part_size "$work/hroot1")" = 2097152 ]; then
	ok 'a hybrid 1GiB root occupies exactly 2097152 sectors'
else
	bad 'a hybrid exact root is wrong'
fi

printf '%s\n' 'root plus fixed partitions must fit the budget'

# 40G root + 64M ESP cannot fit a 40G allocation; nothing may shrink.
if plan uefi-saphira 128G --allocate 40G --root-size 40G > "$work/x" 2>&1; then
	bad '--root-size 40G must not fit inside --allocate 40G'
else
	ok 'an over-budget root plus ESP is refused, nothing resized'
fi
# A root larger than the device is refused even without --allocate.
if plan uefi-saphira 128G --root-size 200G > "$work/x" 2>&1; then
	bad '--root-size 200G must not fit on a 128G device'
else
	ok 'an oversized root is refused'
fi
# But an exact root that does fit is accepted.
if plan uefi-saphira 128G --allocate 40G --root-size 20G > "$work/rfit" 2>&1; then
	ok 'a fitting root plus ESP inside an allocation is accepted'
else
	bad 'a fitting root plus ESP was refused'
fi

printf '%s\n' 'root sizes are validated, not just parsed'

for root_bad in 16M 512K 1000 banana 32Mx; do
	if plan uefi-saphira 128G --root-size "$root_bad" > "$work/x" 2>&1; then
		bad "--root-size '$root_bad' must be refused"
	else
		ok "--root-size '$root_bad' is refused"
	fi
done

if test "$failures" -ne 0; then
	printf 'allocation: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'allocation: OK'
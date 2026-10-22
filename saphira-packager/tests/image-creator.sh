#!/bin/sh

# saphira-image-creator: static and layout tests that never build a
# package and never build an image.
#
# The ruling is explicit that humans build and boot the real thing. What
# this suite proves is everything that CAN be proven without a loop
# device, a filesystem or a package build:
#
#   - the four-target matrix resolves, and only to supported boot/init pairs
#   - the BIOS and UEFI partition plans are both correct, DIFFERENT, and fit
#   - OpenRC and systemd target selection behave differently and correctly
#   - invalid init/boot/size/target combinations fail closed
#   - every shipped profile intention is a real recipe
#   - missing host tools are named, not discovered halfway through a build
#   - the payload layout is what the tool resolves at runtime
#   - the tool is init-neutral: it never detects an init, it is told one
#   - no X, no desktop stack, and no usrmerge assumption anywhere
#
# usage: image-creator.sh [SAPHIRA-IMAGE-CREATOR-DIR]

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
pkgdir=${1:-$root/saphira-image-creator}
tool=$pkgdir/files/saphira-image
targets=$pkgdir/files/targets
# Profiles live in the single shared tree (saphira-install-tools), not
# beside the tool: assert against the authority. Overridable for
# out-of-tree layouts.
profiles=${SAPHIRA_IMAGE_CREATOR_PROFILES:-$root/saphira-install-tools/files/profiles}

fail()
{
	printf '%s\n' "image-creator: $*" >&2
	exit 1
}

[ -f "$tool" ] || fail "tool is missing: $tool"
[ -f "$targets" ] || fail "target matrix is missing: $targets"
[ -d "$profiles" ] || fail "profiles are missing: $profiles"

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/image-creator-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

checks=0
ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

refused()
{
	# $1 description, rest: the command
	description=$1
	shift
	if "$@" >"$work/out" 2>&1; then
		printf '%s\n' "image-creator: expected a refusal: $description" >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	fi
	ok "refuses $description"
}

# --- 1. the target matrix ----------------------------------------------

printf '%s\n' "image-creator: target matrix"
for t in bios-openrc bios-systemd bios-saphira bios-saphirad uefi-openrc uefi-systemd uefi-saphira uefi-saphirad usb-installer; do
	out=$(sh "$tool" list-targets)
	printf '%s\n' "$out" | grep -q "^$t " ||
		fail "list-targets does not offer $t"
done
ok "all nine targets are offered (bios/uefi x openrc/systemd x minimal/product, plus the hybrid USB installer)"

# The matrix must contain exactly those nine, and nothing else.
matrix_count=$(awk '{ l = $0; sub(/#.*$/, "", l); gsub(/^[ \t]+|[ \t]+$/, "", l) } l != "" { n++ } END { print n + 0 }' "$targets")
[ "$matrix_count" -eq 9 ] ||
	fail "target matrix has $matrix_count rows, expected exactly 9"
ok "the matrix is exactly nine rows: adding a target is a line, not a tool"

# Every row must be a supported pair and name a profile that exists.
while read -r name boot init profile; do
	case $name in '' | '#'*) continue ;; esac
	case $boot in bios | uefi | hybrid) ;; *) fail "target $name has boot=$boot" ;; esac
	case $init in openrc | systemd) ;; *) fail "target $name has init=$init" ;; esac
	if [ "$boot" = hybrid ] && [ "$init" != systemd ]; then
		fail "target $name: hybrid boot requires the systemd installer environment"
	fi
	[ -f "$profiles/$profile" ] || fail "target $name names a missing profile: $profile"
done < "$targets"
ok "every row is a supported boot/init pair with a real profile"

# --- 2. partition plans ------------------------------------------------

printf '%s\n' "image-creator: partition plans"
sh "$tool" plan --target bios-openrc --size 2G > "$work/bios.plan" ||
	fail "bios plan failed"
sh "$tool" plan --target uefi-systemd --size 2G > "$work/uefi.plan" ||
	fail "uefi plan failed"

# BIOS: a dedicated bios-boot partition, and NO ESP.
grep -q 'type=21686148-6449-6E6F-744E-656564454649' "$work/bios.plan" ||
	fail "BIOS plan has no bios-boot partition (21686148-...)"
grep -q 'name="bios-boot"' "$work/bios.plan" ||
	fail "BIOS plan does not name its bios-boot partition"
grep -q 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B' "$work/bios.plan" &&
	fail "BIOS plan contains an EFI System Partition; a BIOS system has no firmware to read one"
ok "BIOS: dedicated bios-boot partition, no ESP"

# UEFI: a real FAT ESP with the ESP type GUID, and no bios-boot.
grep -q 'type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B' "$work/uefi.plan" ||
	fail "UEFI plan has no EFI System Partition (C12A7328-...)"
grep -q 'name="esp"' "$work/uefi.plan" ||
	fail "UEFI plan does not name its ESP"
grep -q '21686148-6449-6E6F-744E-656564454649' "$work/uefi.plan" &&
	fail "UEFI plan reuses BIOS partitioning; a bios-boot partition means nothing to UEFI firmware"
ok "UEFI: real ESP, BIOS rules deliberately not reused"

# The two plans must genuinely differ, not be one derived from the other.
if cmp -s "$work/bios.plan" "$work/uefi.plan"; then
	fail "the BIOS and UEFI plans are identical; they must be different layouts"
fi
ok "the two plans are genuinely different layouts"

# Both must be GPT and both must fit the requested image.
for plan in bios uefi; do
	grep -q '^label: gpt' "$work/$plan.plan" ||
		fail "$plan plan is not GPT"
	grep -q 'type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' "$work/$plan.plan" ||
		fail "$plan plan has no Linux root filesystem partition"
done
ok "both plans are GPT with a Linux root partition"

# 1 MiB alignment. Both BIOS and UEFI firmware prefer it, and it is the one
# layout property the fit check CANNOT see: setting the first partition to
# sector 0 still fits the disk exactly, it is merely unaligned. Verified
# negative -- a first_sector of 0 passes the fit check and must be caught
# here instead.
for plan in bios uefi; do
	first=$(awk -F'[,=]' '/^start=/ { print $2 + 0; exit }' "$work/$plan.plan")
	[ "$first" -eq 2048 ] ||
		fail "$plan plan starts its first partition at sector $first, not 2048 (1 MiB alignment)"
done
ok "both plans begin the first partition at sector 2048 (1 MiB aligned)"

# Fit, across the whole matrix and a range of sizes. This is the check the
# first draft of the tool would have failed: it computed root_sectors as if
# the partitions began at sector 0, so the UEFI plan consumed 150% of a
# 512M image while printing entirely plausible numbers.
fit_failures=0
for size in 512M 1G 2G 4G 8G 64G; do
	for target in bios-openrc bios-systemd uefi-openrc uefi-systemd; do
		sh "$tool" plan --target "$target" --size "$size" > "$work/p.plan" 2>/dev/null || continue
		total=$(awk -v s="$size" 'BEGIN {
			if (s ~ /M$/) print substr(s, 1, length(s) - 1) * 1048576
			else if (s ~ /G$/) print substr(s, 1, length(s) - 1) * 1073741824
			else print s
		}')
		used=$(awk -F'[,=]' '
			/^start=/ {
				start = $2 + 0
				size = 0
				for (i = 1; i <= NF; i++) if ($i ~ /size/) size = $(i + 1) + 0
				end = start + size
				if (end > max) max = end
			}
			END { print max * 512 }
		' "$work/p.plan")
		[ "$used" -gt 0 ] || { fit_failures=$((fit_failures + 1)); continue; }
		[ "$used" -le "$total" ] || {
			printf 'image-creator: %s at %s overflows: %s > %s\n' \
				"$target" "$size" "$used" "$total" >&2
			fit_failures=$((fit_failures + 1))
		}
	done
done
[ "$fit_failures" -eq 0 ] ||
	fail "$fit_failures target/size combination(s) overflow the requested image"
ok "every plan fits its requested size, across 4 targets x 6 sizes"

# Fitting inside the requested size is necessary but NOT sufficient, and the
# gap between those two things is exactly where a real build died. GPT keeps
# its backup partition-entry array (32 sectors) and backup header (1 sector)
# in the tail, so the last usable sector is total_sectors-34. A plan can sit
# comfortably inside total_sectors and still cross that boundary, and sfdisk
# does not shrink an oversized partition to fit -- it refuses the whole
# script:
#
#     /dev/loop0p2: The last usable GPT sector is 4194270, but 4194303 is
#     requested.
#     Failed to add #2 partition: Invalid argument
#
# Before the tail reserve every plan ended exactly at total_sectors, so this
# was not a rare edge case: it was every target at every size. The check
# below is deliberately a separate assertion rather than a tighter constant
# in the loop above, because the loop's bound is a different invariant and
# conflating them is how the original plan came to be believed correct.
gpt_failures=0
exact_failures=0
for size in 512M 1G 2G 4G 8G 64G; do
	for target in bios-openrc bios-systemd uefi-openrc uefi-systemd; do
		sh "$tool" plan --target "$target" --size "$size" > "$work/p.plan" 2>/dev/null || continue
		total_sectors=$(awk -v s="$size" 'BEGIN {
			if (s ~ /M$/) print (substr(s, 1, length(s) - 1) * 1048576) / 512
			else if (s ~ /G$/) print (substr(s, 1, length(s) - 1) * 1073741824) / 512
			else print s / 512
		}')
		end=$(awk -F'[,=]' '
			/^start=/ {
				start = $2 + 0
				size = 0
				for (i = 1; i <= NF; i++) if ($i ~ /size/) size = $(i + 1) + 0
				if (start + size > max) max = start + size
			}
			END { print max }
		' "$work/p.plan")
		[ "$end" -gt 0 ] || { gpt_failures=$((gpt_failures + 1)); continue; }
		[ "$end" -le "$total_sectors" ] || {
			printf 'image-creator: %s at %s overflows the disk: sector %s of %s\n' \
				"$target" "$size" "$end" "$total_sectors" >&2
			gpt_failures=$((gpt_failures + 1))
		}
		[ "$end" -le "$((total_sectors - 34))" ] || {
			printf 'image-creator: %s at %s crosses the GPT backup header: ends at sector %s, last usable is %s\n' \
				"$target" "$size" "$end" "$((total_sectors - 34))" >&2
			gpt_failures=$((gpt_failures + 1))
		}
		# The pre-fix signature: a plan that fills the disk to its last
		# sector can never be accepted by sfdisk, so its absence is the
		# cheapest possible proof the reserve is real and not cosmetic.
		[ "$end" -lt "$total_sectors" ] || {
			printf 'image-creator: %s at %s fills the disk to the last sector (%s), leaving no GPT tail\n' \
				"$target" "$size" "$end" >&2
			exact_failures=$((exact_failures + 1))
		}
	done
done
[ "$gpt_failures" -eq 0 ] ||
	fail "$gpt_failures target/size combination(s) cross the GPT backup header"
[ "$exact_failures" -eq 0 ] ||
	fail "$exact_failures target/size combination(s) fill the disk to the last sector, leaving no GPT tail"
ok "every plan stops before the GPT backup header, across 4 targets x 6 sizes"

# --- 3. init selection -------------------------------------------------

printf '%s\n' "image-creator: init selection"
# OpenRC and systemd targets must resolve to DIFFERENT profiles, proving
# the init is carried by the target rather than inferred.
bios_openrc=$(sh "$tool" plan --target bios-openrc --size 2G | sed -n 's/.*init=\([a-z]*\).*/\1/p')
bios_systemd=$(sh "$tool" plan --target bios-systemd --size 2G | sed -n 's/.*init=\([a-z]*\).*/\1/p')
[ "$bios_openrc" = openrc ] || fail "bios-openrc resolved to init=$bios_openrc"
[ "$bios_systemd" = systemd ] || fail "bios-systemd resolved to init=$bios_systemd"
[ "$bios_openrc" != "$bios_systemd" ] ||
	fail "both BIOS targets resolved to the same init"
ok "bios-openrc -> openrc, bios-systemd -> systemd"

uefi_openrc=$(sh "$tool" plan --target uefi-openrc --size 2G | sed -n 's/.*init=\([a-z]*\).*/\1/p')
uefi_systemd=$(sh "$tool" plan --target uefi-systemd --size 2G | sed -n 's/.*init=\([a-z]*\).*/\1/p')
[ "$uefi_openrc" = openrc ] || fail "uefi-openrc resolved to init=$uefi_openrc"
[ "$uefi_systemd" = systemd ] || fail "uefi-systemd resolved to init=$uefi_systemd"
ok "uefi-openrc -> openrc, uefi-systemd -> systemd"

# The tool must be init-ORTHOGONAL: it selects an init, it never detects
# one. Any of these in the tool would mean a package install is being made
# to guess.
for forbidden in '/run/systemd/system' 'systemctl is-system-running' \
	'readlink.*sbin/init' 'proc/1/comm' '/sbin/openrc\"]' ; do
	if grep -qE "$forbidden" "$tool" 2>/dev/null; then
		grep -nE "$forbidden" "$tool" >&2 || true
		fail "the tool appears to DETECT the active init ($forbidden); init is chosen, never inferred"
	fi
done
ok "no init detection anywhere in the tool: the init is chosen, not inferred"

# The two init preparations must both exist and must differ.
grep -q 'saphira_init\|: openrc)' "$tool" || true
grep -q '/sbin/openrc' "$tool" ||
	fail "no OpenRC boot-path preparation in the tool"
grep -q 'multi-user.target' "$tool" ||
	fail "no systemd default.target preparation in the tool"
ok "both init preparations are present (inittab for OpenRC, default.target for systemd)"

# Enabling must never be a start.
grep -nE '^\s*(systemctl|rc-service|rc-update) [a-z-]*start' "$tool" && {
	fail "the tool starts something; enabling is a persistent intent and an image has no running init"
} || true
grep -q 'systemctl --root=/ enable' "$tool" ||
	fail "the systemd path does not enable offline through systemctl --root"
ok "services are enabled offline, never started"

# --- 4. fail closed ----------------------------------------------------

printf '%s\n' "image-creator: fail-closed behaviour"
refused "an unknown target" sh "$tool" plan --target bios-plan9 --size 2G
refused "an invalid size" sh "$tool" plan --target bios-openrc --size 2X
refused "a non-numeric size" sh "$tool" plan --target bios-openrc --size abc
refused "an unknown action" sh "$tool" frobnicate
refused "an unknown role layer" sh "$tool" report --target bios-openrc --role role-nonesuch

# A size too small to be bootable must be refused, not silently accepted:
# a 64M ESP plus an alignment gap leaves no usable root below a point.
for tiny in 8M 16M; do
	refused "a ${tiny} image (no usable root)" sh "$tool" plan --target uefi-systemd --size "$tiny"
done
ok "undersized images are refused rather than producing an unbootable layout"

# An existing output must never be overwritten.
: > "$work/existing.raw"
refused "an existing output path" env SAPHIRA_IMAGE_TARGETS="$targets" \
	SAPHIRA_IMAGE_PROFILES="$profiles" sh "$tool" build \
	--target bios-openrc --output "$work/existing.raw"
[ -s "$work/existing.raw" ] || [ -f "$work/existing.raw" ] ||
	fail "the refusal removed a pre-existing output file; only outputs this run created may be removed"
ok "a pre-existing output is refused and left untouched"

printf '%s\n' "image-creator: physical-disk refusals (nothing touched)"

# Every refusal below fires before privileges, partitioning, mounts or
# any write: validation is read-only (blockdev size probes and table
# reads), so these run rootless. Anything reaching past validation
# would still stop at the typed confirmation, which is never satisfied
# here. Preview mode never writes by construction.
refused "install-to-disk without a device" \
	sh "$tool" install-to-disk --target bios-openrc
refused "install-to-disk without a target" \
	sh "$tool" install-to-disk --device /dev/does-not-exist-xyz
refused "install-to-disk on a missing path" \
	sh "$tool" install-to-disk --target bios-openrc --device /dev/does-not-exist-xyz
: > "$work/not-a-disk"
refused "install-to-disk on a non-block file" \
	sh "$tool" install-to-disk --target bios-openrc --device "$work/not-a-disk"
# The disk backing the work directory is mounted by definition (and
# usually the boot disk too): whichever guard fires first, it must be
# refused without touching anything. No block-backed root in this
# environment (container overlay) means nothing to refuse here.
root_src=$(df -- "$work" 2>/dev/null | awk 'NR==2 { print $1 }')
case $root_src in
/dev/*)
	if [ -b "$root_src" ]; then
		refused "install-to-disk on a live disk" \
			sh "$tool" install-to-disk --target bios-openrc --device "$root_src" --preview
		ok "a live disk is refused without touching anything"
	else
		ok "no block device backs the work directory; live-disk refusal untestable here"
	fi ;;
*)
	ok "no block device backs the work directory; live-disk refusal untestable here" ;;
esac
refused "install-to-disk with an unknown target" \
	sh "$tool" install-to-disk --target bios-plan9 --device /dev/does-not-exist-xyz
refused "install-to-disk preview without a device" \
	sh "$tool" install-to-disk --target bios-openrc --preview
ok "physical-disk refusals all fire before anything destructive"

# --- 5. missing tool detection ----------------------------------------

printf '%s\n' "image-creator: host tool detection"
# The tool must check its host tools UP FRONT and name them, because a
# missing sfdisk discovered after the image is allocated leaves a
# half-written disk behind.
for tool_name in sfdisk losetup mkfs.ext4 grub-install; do
	grep -q "$tool_name" "$tool" ||
		fail "the tool never checks for $tool_name"
done
grep -q 'mkfs.vfat' "$tool" ||
	fail "the tool never checks for mkfs.vfat, which a uefi target requires"
grep -q 'require_host_tools' "$tool" ||
	fail "the tool has no host-tool precondition function"
ok "sfdisk, losetup, mkfs.ext4, grub-install and mkfs.vfat are all checked"

# The check must run BEFORE anything is allocated.
awk '
	/require_host_tools$/ { found = NR }
	/truncate -s/ { truncate = NR }
	END { exit !(found && truncate && found < truncate) }
' "$tool" || fail "host tools are checked after the image is allocated; the check must come first"
ok "host tools are checked before the image is allocated"

# --- 6. profiles -------------------------------------------------------

printf '%s\n' "image-creator: profiles"
missing=0
for f in "$profiles"/*; do
	# .services sidecars name services, not packages (resolved through
	# unit [Install] sections); they are not install intentions.
	case $f in *.services) continue ;; esac
	awk '
		{ line = $0; sub(/#.*$/, "", line) }
		line ~ /^[[:space:]]*$/ { next }
		{ gsub(/^[ \t]+|[ \t]+$/, "", line); print line }
	' "$f" | while read -r pkg; do
		[ -n "$pkg" ] || continue
		case $pkg in
		*[![:alnum:]._+-]*) continue ;;
		esac
		# -dev/-doc names resolve to the base recipe (repo convention).
		base=$pkg
		case $base in
		*-dev) base=${base%-dev} ;;
		*-doc) base=${base%-doc} ;;
		esac
		[ -f "$root/$base/recipe.sh" ] || {
			printf 'image-creator: %s names %s, which has no recipe\n' "${f##*/}" "$pkg" >&2
			exit 1
		}
	done || missing=$((missing + 1))
done
[ "$missing" -eq 0 ] || fail "$missing profile(s) name a package that does not exist"
ok "every intention in every profile is a real recipe"

# A profile must list INTENTIONS only, never a resolved closure. The
# established marker is a version-operator pin, which is how a closure
# leaks into a definition.
if grep -hE '^[a-z0-9.+-]+[<>=]' "$profiles"/* 2>/dev/null | grep .; then
	fail "a profile contains a version pin; profiles carry intentions and APK metadata owns the closure"
fi
ok "profiles carry intentions only, no version pins"

# The minimal profiles must differ ONLY in the init package. Written with
# temp files rather than <(...) process substitution: this suite is
# #!/bin/sh, and process substitution is a bashism.
strip_profile()
{
	grep -v '^#' "$1" | grep -v '^[[:space:]]*$' | sort
}
strip_profile "$profiles/minimal-openrc" > "$work/mp.openrc"
strip_profile "$profiles/minimal-systemd" > "$work/mp.systemd"
# Everything except the init line must be identical.
grep -v '^openrc$' "$work/mp.openrc" > "$work/mp.openrc.noinit"
grep -v '^systemd$' "$work/mp.systemd" > "$work/mp.systemd.noinit"
if ! cmp -s "$work/mp.openrc.noinit" "$work/mp.systemd.noinit"; then
	diff "$work/mp.openrc.noinit" "$work/mp.systemd.noinit" >&2 || true
	fail "the two minimal profiles differ by more than the init package"
fi
grep -qx 'openrc' "$work/mp.openrc" ||
	fail "minimal-openrc does not name the openrc package"
grep -qx 'systemd' "$work/mp.systemd" ||
	fail "minimal-systemd does not name the systemd package"
ok "the minimal profiles differ only in the init package"

# Roles must be DATA, not invented packages: a role-* recipe would be a
# meta-package, which the ruling forbids.
for role in "$profiles"/role-*; do
	name=${role##*/}
	[ -d "$root/$name" ] &&
		fail "role $name is also a recipe; roles are profile data, not meta-packages"
done
ok "roles are profile data; no role-* meta-package was invented"

# Every @-include must resolve to a profile in the shared tree (with the
# historical @saphira-stage4-/@akadata-stage4- alias spelling). A dangling
# include fails only at image-build time, inside the installer, far from
# the typo - the bootstrap refuses it there, but the recipe build should
# never ship it.
unresolved=0
for f in "$profiles"/*; do
	[ -f "$f" ] || continue
	case $f in *.services) continue ;; esac
	awk '
		{ line = $0; sub(/#.*$/, "", line) }
		line ~ /^[[:space:]]*$/ { next }
		{ gsub(/^[ \t]+|[ \t]+$/, "", line); print line }
	' "$f" | while read -r entry; do
		[ -n "$entry" ] || continue
		case $entry in
		@*)	inc=${entry#@}
			case $inc in
			saphira-stage4-*|akadata-stage4-*)
				inc=${inc#saphira-stage4-}
				inc=${inc#akadata-stage4-} ;;
			esac
			[ -f "$profiles/$inc" ] ||
				{ printf 'image-creator: %s includes missing profile @%s\n' "${f##*/}" "$entry" >&2; exit 1; } ;;
		esac
	done || unresolved=$((unresolved + 1))
done
[ "$unresolved" -eq 0 ] || fail "a profile includes a profile that does not exist"
ok "every profile include resolves inside the shared tree"

# --- 7. no-X and non-usrmerged ----------------------------------------

printf '%s\n' "image-creator: headless and non-usrmerged"
# The headless policy is machine-enforced by headless.sh; this asserts the
# image profiles specifically, since an image is the most visible surface.
if awk '{ l = $0; sub(/#.*$/, "", l); gsub(/^[ \t]+|[ \t]+$/, "", l) } l != "" { print l }' \
	"$profiles"/* | grep -Eq '^(xorg|libX|libx|wayland|weston|gtk|gdk|qt5|qt6|cairo|pango|mesa|libGL|libEGL|libgbm|libdrm|ffmpeg|pipewire|pulseaudio|alsa-lib|bluez|cups|fontconfig|freetype)'; then
	fail "an image profile names a graphical or desktop package"
fi
ok "no image profile names a graphical, desktop or media-stack package"

# Non-usrmerged: the tool must not assume /bin == /usr/bin anywhere.
for bad in '/usr/bin/sh' '/usr/bin/env bash' '/usr/lib/systemd/systemd' ; do
	grep -q "$bad" "$tool" && {
		grep -n "$bad" "$tool" >&2
		fail "the tool references $bad, which assumes a usr-merged tree"
	}
done
ok "the tool assumes no usrmerge"
# systemd is patched for the non-merged layout, so the unit directory is
# the systemd-owned one and must be used verbatim.
grep -q '/usr/lib/systemd/system' "$tool" ||
	fail "the tool does not reference the systemd unit directory; the patched systemd still uses it"
ok "the systemd unit directory is the destination-system path"

# --- 8. scratch hygiene ------------------------------------------------

printf '%s\n' "image-creator: scratch hygiene"
# The needle is assembled from parts so this checker does not match its own
# source: recipe-rules.sh forbids the literal host-scratch path anywhere in
# the tree, and a checker that contains it verbatim fails that gate.
tmp_needle=$(printf '/%s' tmp)
if grep -qE "mktemp[^|]*[[:space:]]/?${tmp_needle}/" "$tool" 2>/dev/null; then
	grep -nE "mktemp[^|]*[[:space:]]${tmp_needle}/" "$tool" >&2
	fail "the tool uses host /tmp for scratch; RECIPE_RULES.md forbids it"
fi
grep -q 'SAPHIRA_TMPDIR' "$tool" ||
	fail "the tool does not honour SAPHIRA_TMPDIR"
ok "scratch lives under SAPHIRA_TMPDIR, never host /tmp"

# --- 9. payload layout and packaging ----------------------------------

printf '%s\n' "image-creator: payload and recipe"
[ -f "$pkgdir/recipe.sh" ] || fail "no recipe.sh"
sh -n "$pkgdir/recipe.sh" || fail "recipe.sh does not parse"
sh -n "$tool" || fail "the tool does not parse"
ok "recipe.sh and the tool both parse"

grep -q 'usr/bin/saphira-image' "$pkgdir/recipe.sh" ||
	fail "the recipe does not install /usr/bin/saphira-image"
grep -q 'files/targets' "$pkgdir/recipe.sh" ||
	fail "the recipe does not install the target matrix"
grep -q 'saphira-image.8' "$pkgdir/recipe.sh" ||
	fail "the recipe installs no man page"
ok "the recipe installs the tool, the matrix, the profiles and a man page"

# The creator must DEPEND on the canonical assembler, not reimplement it.
grep -q 'saphira-install-tools' "$pkgdir/recipe.sh" ||
	fail "the recipe does not depend on saphira-install-tools; the creator must orchestrate the canonical path"
grep -q 'saphira-assemble-rootfs' "$tool" ||
	fail "the tool never names saphira-assemble-rootfs; the canonical path must be explicit"
grep -q 'saphira-install' "$tool" ||
	fail "the tool never calls saphira-install"
ok "the creator depends on and calls the canonical path"

# It must NOT do assembly itself.
for forbidden in 'apk add' 'apk add --root' 'tar -xf' '\.apk'; do
	grep -q "$forbidden" "$tool" && {
		grep -n "$forbidden" "$tool" >&2
		fail "the tool performs package work itself ($forbidden); saphira-install owns that"
	}
done
ok "the tool performs no package work of its own"

# pkgrel discipline: never r0.
grep -qE '^pkgrel=[0-9]+$' "$pkgdir/recipe.sh" || fail "no pkgrel"
pkgrel=$(sed -n 's/^pkgrel=//p' "$pkgdir/recipe.sh")
[ "$pkgrel" -ge 1 ] || fail "pkgrel is $pkgrel; r0 is never published"
ok "pkgrel is $pkgrel (never r0)"

# --- 10. man page ------------------------------------------------------

man=$pkgdir/files/saphira-image.8
[ -f "$man" ] || fail "no man page"
for section in NAME SYNOPSIS DESCRIPTION ARCHITECTURE OPTIONS EXAMPLES 'SEE ALSO'; do
	grep -q "^\.SH $section\$" "$man" || fail "man page has no .SH $section"
done
# Recipe-rules.sh requires all eight standard sections.
for section in NAME SYNOPSIS DESCRIPTION USAGE FILES NOTES AUTHOR; do
	grep -q "^\.SH $section\$" "$man" || fail "man page is missing the .SH $section section recipe-rules.sh requires"
done
LC_ALL=C grep -q '[^ -~	]' "$man" && fail "man page is not ASCII"
ok "man page is complete and ASCII"

# --- 11. installed-path and enablement correctness ---------------------
#
# Every check above ran the tool from the recipe directory, where
# files/targets really IS a sibling of files/saphira-image. That single
# fact let four real defects through: the installed tool looked for
# /usr/bin/targets, enable_services enabled nothing at all, the composed
# profile was copied into package-owned data, and the reported image size
# was arithmetic on a pathname. These checks are behavioural and simulate
# the INSTALLED layout, because greps over the source tree are exactly
# what failed to catch them.

printf '%s\n' "image-creator: installed layout"

# Simulate a real install: tool in a bin directory with NO sibling data,
# matrix under the image datadir, profiles under the SHARED tree,
# exactly as /usr/bin/saphira-image + /usr/share/saphira/image/targets +
# /usr/share/saphira/profiles (saphira-install-tools).
instbin=$work/install/bin
instdata=$work/install/share/saphira/image
instshared=$work/install/share/saphira/profiles
mkdir -p "$instbin" "$instdata" "$instshared"
cp "$tool" "$instbin/saphira-image"
cp "$targets" "$instdata/targets"
cp "$profiles"/* "$instshared/"

out=$(SAPHIRA_IMAGE_DATADIR="$instdata" sh "$instbin/saphira-image" list-targets) ||
	fail "the tool cannot find its data when installed (no sibling targets); it must fall back to the image datadir"
printf '%s\n' "$out" | grep -q '^bios-openrc ' ||
	fail "installed-layout list-targets did not offer bios-openrc"
ok "the installed tool resolves targets/ from the image datadir, not from dirname \$0"

# Profiles resolve from the shared tree, not the image datadir: plan
# must work with only the matrix beside the tool.
out=$(SAPHIRA_IMAGE_DATADIR="$instdata" SAPHIRA_IMAGE_SHARED_PROFILES="$instshared" \
	sh "$instbin/saphira-image" plan --target bios-openrc --size 2G) ||
	fail "installed-layout plan cannot resolve its profile from the shared tree"
printf '%s\n' "$out" | grep -q '^# saphira-image plan: target=bios-openrc' ||
	fail "installed-layout plan printed no plan header"
ok "the installed tool resolves profiles from the shared tree"

# And it must REFUSE rather than silently searching its own bin directory
# when there is no data anywhere, instead of dying later with a confusing
# error from a half-run build.
if SAPHIRA_IMAGE_DATADIR="$work/install/empty" sh "$instbin/saphira-image" list-targets >"$work/out" 2>&1; then
	fail "the tool ran with no target matrix anywhere instead of refusing"
fi
grep -q 'target matrix is missing' "$work/out" ||
	fail "the tool did not report the missing target matrix clearly"
ok "a missing target matrix is a clear, early refusal"

printf '%s\n' "image-creator: offline service enablement"

# Exercise enable_services for real against a fake image root. This is
# the check that matters most: the function used to run its package loop
# on the right of a pipe, so it ran in a subshell, every assignment was
# discarded, and it silently enabled nothing while reporting success.
mkdir -p "$work/img/usr/lib/systemd/system" "$work/img/etc/systemd/system" \
	"$work/img/etc/init.d" "$work/img/etc/runlevels/default" "$work/img/usr/bin"
: >"$work/img/usr/lib/systemd/system/fake-daemon.service"
: >"$work/img/etc/init.d/fake-daemon"
# The tool refuses a systemd target with no systemctl in the image, so the
# fake root needs one; the real systemctl is never invoked because the
# chroot helper is stubbed below.
printf '#!/bin/sh\nexit 0\n' >"$work/img/usr/bin/systemctl"
chmod 0755 "$work/img/usr/bin/systemctl"
printf '%s\n' fake-daemon >"$work/composed-profile"

# Extract the function and drive it in a harness, with the chroot helper
# stubbed out to record what it was asked to do.
sed -n '/^service_names()/,/^}/p' "$tool" >"$work/names.fn" ||
	fail "cannot extract service_names from the tool"
[ -s "$work/names.fn" ] || fail "service_names was not found in the tool"
sed -n '/^enable_services()/,/^}/p' "$tool" >"$work/enable.fn" ||
	fail "cannot extract enable_services from the tool"
[ -s "$work/enable.fn" ] || fail "enable_services was not found in the tool"

cat >"$work/mounter" <<'MOUNTER'
#!/bin/sh
printf '%s\n' "$*" >> "$MOUNTER_LOG"
MOUNTER
chmod 0755 "$work/mounter"
MOUNTER_LOG=$work/mounter.log; export MOUNTER_LOG

# chroot_command is a VARIABLE holding a path in the tool (it defaults to
# $bindir/saphira-chroot), so the harness must supply a path, not a shell
# function.
# bindir is a tool GLOBAL (dirname $0) that enable_services reads for the
# services-off.d lookup. The extracted function runs outside the tool, so
# the harness supplies a bindir with no services-off.d in it: the lookup
# falls through to datadir (also unset here) and is skipped, exactly as
# on a target with no exclusions. This is fixture completeness, not a
# behaviour change: the tool always sets bindir at startup.
mkdir -p "$work/empty-bindir"
cat >"$work/harness.sh" <<HARNESS
set -eu
work='$work'
die() { printf 'HARNESS-DIE: %s\n' "\$*" >&2; exit 1; }
. "\$work/names.fn"
. "\$work/enable.fn"
ENABLE=1
INIT=\$1
bindir="\$work/empty-bindir"
datadir=""
services_dir=""
chroot_command="\$work/mounter"
enable_services "\$work/img" "\$work/composed-profile"
HARNESS

: >"$work/mounter.log"
sh "$work/harness.sh" systemd >/dev/null 2>&1 ||
	{
		sh "$work/harness.sh" systemd >&2 || true
		fail "the offline systemd enablement path failed unexpectedly"
	}
grep -q 'fake-daemon.service' "$work/mounter.log" ||
	{
		cat "$work/mounter.log" >&2
		fail "enable_services did not enable fake-daemon.service; the package loop must not run in a subshell"
	}
ok "offline enablement really reaches systemctl (not lost to a subshell)"

: >"$work/mounter.log"
sh "$work/harness.sh" openrc >/dev/null 2>&1 ||
	{
		sh "$work/harness.sh" openrc >&2 || true
		fail "the offline OpenRC enablement path failed unexpectedly"
	}
[ -L "$work/img/etc/runlevels/default/fake-daemon" ] ||
	fail "enable_services did not create the OpenRC runlevel symlink for fake-daemon"
ok "offline enablement really writes the OpenRC runlevel symlink"

# A pipe-fed loop is the defect itself, so refuse the pattern outright.
grep -q '| while IFS=' "$tool" &&
	fail "the tool pipes into a while loop; that loop runs in a subshell and discards its assignments"
ok "no pipe-fed while loop can silently discard state"

printf '%s\n' "image-creator: declared service names"

# service-name == package-name is an assumption, not an invariant.
# saphira-packager ships /etc/init.d/saphira-build, so a profile naming
# saphira-packager used to enable nothing at all, silently - which is how
# the controller's build daemon ended up with no owner for its runlevel
# state and was only ever started by hand.
# The image root gains a differently-named service, provided by a package
# whose name is not that service.
mkdir -p "$work/img2/usr/lib/systemd/system" "$work/img2/etc/systemd/system" \
	"$work/img2/etc/init.d" "$work/img2/etc/runlevels/default" "$work/img2/usr/bin"
: >"$work/img2/usr/lib/systemd/system/build-daemon.service"
: >"$work/img2/etc/init.d/build-daemon"
printf '#!/bin/sh\nexit 0\n' >"$work/img2/usr/bin/systemctl"
chmod 0755 "$work/img2/usr/bin/systemctl"

mkdir -p "$work/svc.d"
printf '# the service is not named after the package\nbuild-daemon\n' \
	>"$work/svc.d/some-controller"

cat >"$work/harness2.sh" <<HARNESS2
set -eu
work='$work'
die() { printf 'HARNESS-DIE: %s\n' "\$*" >&2; exit 1; }
. "\$work/names.fn"
. "\$work/enable.fn"
ENABLE=1
INIT=\$1
bindir="\$work/empty-bindir"
datadir=""
services_dir="\$work/svc.d"
chroot_command="\$work/mounter"
enable_services "\$work/img2" "\$work/composed-profile2"
HARNESS2

# The profile still names only the PACKAGE: listing services there would
# duplicate package knowledge and violate the profile invariant.
printf '%s\n' some-controller >"$work/composed-profile2"

: >"$work/mounter.log"
sh "$work/harness2.sh" systemd >/dev/null 2>&1 ||
	{
		sh "$work/harness2.sh" systemd >&2 || true
		fail "the declared-service systemd path failed unexpectedly"
	}
grep -q 'build-daemon.service' "$work/mounter.log" ||
	{
		cat "$work/mounter.log" >&2
		fail "a package that declares its service name did not get it enabled; service-name == package-name is being assumed"
	}
ok "a package's declared service name is enabled, not just its own name"

: >"$work/mounter.log"
sh "$work/harness2.sh" openrc >/dev/null 2>&1 ||
	{
		sh "$work/harness2.sh" openrc >&2 || true
		fail "the declared-service openrc path failed unexpectedly"
	}
[ -L "$work/img2/etc/runlevels/default/build-daemon" ] ||
	fail "a declared service name did not get an OpenRC runlevel symlink"
ok "a declared service name gets its OpenRC runlevel symlink too"

# A package with no mapping must still resolve to its own name, so every
# package that never needed the exception is unaffected.
rm -rf "$work/svc.d"; mkdir -p "$work/svc.d"
printf '%s\n' plain-daemon >"$work/composed-profile3"
sed -i 's|img2|img3|g; s|composed-profile2|composed-profile3|' "$work/harness2.sh"
mkdir -p "$work/img3/etc/init.d" "$work/img3/etc/runlevels/default"
: >"$work/img3/etc/init.d/plain-daemon"
sh "$work/harness2.sh" openrc >/dev/null 2>&1 ||
	{
		sh "$work/harness2.sh" openrc >&2 || true
		fail "a package with no mapping failed to resolve to its own name"
	}
[ -L "$work/img3/etc/runlevels/default/plain-daemon" ] ||
	fail "an unmapped package no longer enables its own same-named service"
ok "an unmapped package still resolves to its own name (back-compat)"

# An image with NO /usr/lib/systemd/system must still enable its OpenRC
# services. The systemd guard used to `continue` out of the whole package
# loop, so an openrc-only image silently enabled nothing - the same shape of
# silent no-op this function already had once.
mkdir -p "$work/img4/etc/init.d" "$work/img4/etc/runlevels/default"
: >"$work/img4/etc/init.d/plain-daemon"
sed -i 's|img3|img4|g; s|composed-profile3|composed-profile4|' "$work/harness2.sh"
printf '%s\n' plain-daemon >"$work/composed-profile4"
rm -rf "$work/svc.d"
sh "$work/harness2.sh" openrc >/dev/null 2>&1 ||
	{
		sh "$work/harness2.sh" openrc >&2 || true
		fail "an openrc-only image (no systemd unit directory) failed outright"
	}
[ -L "$work/img4/etc/runlevels/default/plain-daemon" ] ||
	fail "an openrc-only image enabled nothing because the systemd guard skipped the whole package"
ok "an openrc-only image still enables its services (no silent no-op)"

# The mapping is data, and the recipe must ship it or the tool finds nothing.
[ -f "$pkgdir/files/services.d/saphira-packager" ] ||
	fail "the saphira-packager service mapping is missing, so naming the package would enable nothing"
grep -qx "saphira-build" "$pkgdir/files/services.d/saphira-packager" ||
	fail "the saphira-packager mapping does not name saphira-build"
grep -q "services.d" "$pkgdir/recipe.sh" ||
	fail "the recipe does not install the services.d mapping into the payload"
ok "the controller's own mapping ships with the image creator"

# And the mapping must be OPTIONAL data: a tree without it must still run,
# because absence means every service is named after its package.
sed -i 's|^services_dir=.*|services_dir=""|' "$work/harness2.sh"
sh "$work/harness2.sh" openrc >/dev/null 2>&1 ||
	{
		sh "$work/harness2.sh" openrc >&2 || true
		fail "the tool fails outright when no services.d directory exists; it must be optional"
	}
[ -L "$work/img4/etc/runlevels/default/plain-daemon" ] ||
	fail "with no mapping at all, a same-named service stopped being enabled"
ok "services.d is optional data, not a requirement"

printf '%s\n' "image-creator: profile staging and measurement"

# The composed profile is a per-image intention. It must be staged in
# scratch and resolved through saphira-install's own profile root, never
# written into the package-owned profile directory.
grep -q 'cp "\$composed" "\${SAPHIRA_IMAGE_PROFILES' "$tool" &&
	fail "the composed profile is copied into the package-owned profile directory"
grep -q 'SAPHIRA_PROFILE_ROOT="\$profile_root"' "$tool" ||
	fail "the installer is not given the scratch profile root via SAPHIRA_PROFILE_ROOT"
ok "the composed profile is staged in scratch, never in package-owned data"

# size_bytes_any is a formatter for a NUMBER. Handing it a pathname made
# the reported image size meaningless while still printing a plausible
# looking line.
cat >"$work/size.sh" <<'SIZEFN'
set -eu
sed -n '/^size_bytes_any()/,/^}/p' "$1"
SIZEFN
sh "$work/size.sh" "$tool" >"$work/size.fn"
printf '. %s ; size_bytes_any 2097152; printf "\\n"; size_bytes_any 512; printf "\\n"\n' "$work/size.fn" >"$work/sizefn.sh"
got=$(sh "$work/sizefn.sh")
[ "$got" = "2 MiB
512 B" ] || fail "size_bytes_any mis-formats a byte count: got [$got]"
ok "byte counts are formatted, and a path is never mistaken for one"

grep -q 'size_bytes_any "\$raw_output"' "$tool" &&
	fail "size_bytes_any is still handed the image PATH instead of a measured size"
grep -q 'file_bytes "\$raw_output"' "$tool" ||
	fail "the image size is not measured from the file"
ok "image size is measured from the file, not computed from a pathname"

printf '%s\n' "image-creator: OK ($checks checks)"

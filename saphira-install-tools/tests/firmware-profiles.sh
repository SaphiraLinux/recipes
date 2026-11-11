#!/bin/sh
# Firmware placement in the install profiles, resolved the way
# saphira-image resolves them.
#
# EFI-specific utilities must never reach a BIOS installation, and a
# UEFI installation must carry its ESP and NVRAM tooling. The rule
# lives in saphira-image (automatic firmware layers per target boot),
# and this pins the resolved outcome per matrix target: bios-*
# compositions contain no efibootmgr, uefi-* compositions contain
# efibootmgr plus dosfstools plus grub, and the universal installer
# keeps both toolchains explicitly (the firmware booted is not
# necessarily the firmware targeted).
#
# Static resolution only: profile files plus the matrix, no builder,
# no repository. Dependency closure belongs to APK metadata and is
# proven by the repository index, not here.

set -u

here=$(cd -- "$(dirname -- "$0")" && pwd)
profiles_dir=${SAPHIRA_PROFILE_ROOT:-$here/../files/profiles}
targets_file=${SAPHIRA_IMAGE_TARGETS:-$here/../../saphira-image-creator/files/targets}

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

[ -d "$profiles_dir" ] || { echo "profiles not found: $profiles_dir" >&2; exit 2; }
[ -f "$targets_file" ] || { echo "targets not found: $targets_file" >&2; exit 2; }

# Resolve @-includes the way saphira-bootstrap does: one level of
# @name / @saphira-stage4-name indirection, recursive, with a visited
# set against cycles. Comments and blank lines are ignored. The
# visited set resets on every top-level resolution: sharing it across
# targets would make the second target resolve to nothing.
resolve_into()
{
	file=$1
	case " $seen " in
	*" $file "*) return 0 ;;
	esac
	seen="$seen$file "
	while IFS= read -r line || [ -n "$line" ]; do
		entry=$(printf '%s' "$line" | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		[ -n "$entry" ] || continue
		case $entry in
		@saphira-stage4-*) resolve_into "${entry#@saphira-stage4-}" ;;
		@akadata-stage4-*) resolve_into "${entry#@akadata-stage4-}" ;;
		@*) resolve_into "${entry#@}" ;;
		*) printf '%s\n' "$entry" ;;
		esac
	done < "$profiles_dir/$file"
}

resolve_profile()
{
	seen=
	resolve_into "$1"
}

# The firmware rule, mirroring saphira-image append_firmware_layer:
# bios gains base-bios, uefi gains base-efi, hybrid gains neither
# (installer profiles carry both toolchains explicitly).
composed()
{
	profile=$1
	boot=$2
	seen=
	resolve_into "$profile"
	case $boot in
	bios) resolve_into base-bios ;;
	uefi) resolve_into base-efi ;;
	hybrid) : ;;
	esac
}

has() { printf '%s' "$1" | grep -qx "$2"; }

echo "install profile firmware placement"

# --- 1. the firmware layers exist and mean what they claim --------------
if [ -f "$profiles_dir/base-bios" ] && [ -f "$profiles_dir/base-efi" ]; then
	ok 'base-bios and base-efi exist'
else
	no 'base-bios and base-efi exist'
fi
efi_pkgs=$(resolve_profile base-efi 2>/dev/null | sort -u)
if has "$efi_pkgs" efibootmgr && has "$efi_pkgs" dosfstools; then
	ok 'base-efi carries NVRAM and ESP tooling'
else
	no 'base-efi carries NVRAM and ESP tooling'
fi

# --- 2. generic profiles stay firmware-neutral -----------------------------
for p in base base-system; do
	pkgs=$(resolve_profile "$p" 2>/dev/null | sort -u)
	if has "$pkgs" efibootmgr; then
		no "$p must not name efibootmgr (UEFI-only)"
	else
		ok "$p names no efibootmgr"
	fi
done

# --- 3. every matrix target resolves to the firmware it boots --------------
seen_targets=0
while IFS= read -r line || [ -n "$line" ]; do
	case $line in ''|'#'*) continue ;; esac
	set -- $line
	name=$1 boot=$2 profile=$4
	[ -n "$name" ] && [ -n "$boot" ] && [ -n "$profile" ] || continue
	seen_targets=$((seen_targets + 1))
	pkgs=$(composed "$profile" "$boot" 2>/dev/null | sort -u)
	case $boot in
	bios)
		if has "$pkgs" efibootmgr; then
			no "$name (bios) must not resolve efibootmgr"
		else
			ok "$name (bios) resolves no efibootmgr"
		fi
		if has "$pkgs" grub; then
			ok "$name (bios) resolves grub"
		else
			no "$name (bios) resolves grub"
		fi
		;;
	uefi)
		missing=
		for want in efibootmgr dosfstools grub; do
			has "$pkgs" "$want" || missing="$missing $want"
		done
		if [ -z "$missing" ]; then
			ok "$name (uefi) resolves ESP, NVRAM and bootloader tooling"
		else
			no "$name (uefi) is missing:$missing"
		fi
		;;
	hybrid)
		# Universal installers carry both toolchains explicitly in
		# their own profiles, never through the firmware layer.
		if has "$pkgs" grub; then
			ok "$name (hybrid) resolves grub"
		else
			no "$name (hybrid) resolves grub"
		fi
		;;
	esac
done < "$targets_file"
[ "$seen_targets" -gt 0 ] || no 'the target matrix yielded no targets'

# --- 4. the universal installer keeps both toolchains ------------------------
usb=$(composed usb-installer hybrid 2>/dev/null | sort -u)
missing=
for want in grub efibootmgr dosfstools; do
	has "$usb" "$want" || missing="$missing $want"
done
if [ -z "$missing" ]; then
	ok 'usb-installer carries both firmware toolchains explicitly'
else
	no "usb-installer is missing:$missing"
fi

# --- 4b. the installer appliance stays removable-only ---------------------------
# image-installer-appliance installs both BIOS and UEFI systems, but
# only through GRUB's removable fallback (BOOTX64.EFI): it deliberately
# carries no NVRAM tooling, so an efibootmgr appearance here is a
# design change, not an accident. A hybrid image test must still prove
# both boot paths work; this pins the package half of that proof.
appliance=$(composed image-installer-appliance hybrid 2>/dev/null | sort -u)
missing=
for want in grub dosfstools; do
	has "$appliance" "$want" || missing="$missing $want"
done
if [ -z "$missing" ]; then
	ok 'image-installer-appliance carries the removable-path tooling'
else
	no "image-installer-appliance is missing:$missing"
fi
if has "$appliance" efibootmgr; then
	no 'image-installer-appliance must stay NVRAM-free by design'
else
	ok 'image-installer-appliance stays NVRAM-free by design'
fi

# --- 5. role-wireless stays a client role --------------------------------------
role=$(resolve_profile role-wireless 2>/dev/null | sort -u)
if has "$role" wireless-regdb && has "$role" iw; then
	ok 'role-wireless carries regdb and iw'
else
	no 'role-wireless carries regdb and iw'
fi
leak=
for want in wpa_supplicant iwd wireless-tools hostapd; do
	has "$role" "$want" && leak="$leak $want"
done
if [ -z "$leak" ]; then
	ok 'role-wireless pulls no associator, legacy tools or AP stack'
else
	no "role-wireless leaks:$leak"
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "install profile firmware placement: OK"

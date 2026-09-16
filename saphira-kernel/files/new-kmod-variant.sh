#!/bin/sh
# new-kmod-variant.sh -- stamp a new per-kernel kmod recipe from the nearest
# existing variant of the same family. Adding kernel 7.3.1 later is:
#   new-kmod-variant.sh saphira-zfs 7.3.1
#
# Usage: new-kmod-variant.sh <base> <kver>
#   base: saphira-zfs | nvidia-open | saphira-drbd9
#   kver: short kernel version matching a staged tree dir (linux-<kver>),
#         e.g. 7.2.3, 7.3-rc1
#
# Copies the highest existing <base>-* variant, substitutes the package
# name, KVER_SHORT, headers pin and description, verifies the source
# tarball (and patch, for nvidia) rode along, and syntax-checks. The
# shared build logic in saphira-kernel/files/kmod-*.sh is untouched:
# thin recipes differ only in KVER_SHORT (+ headers pin).

set -eu

die()
{
	printf 'new-kmod-variant: %s\n' "$*" >&2
	exit 1
}

[ "$#" -eq 2 ] || die "usage: $0 <saphira-zfs|nvidia-open|saphira-drbd9> <kver>"
base=$1
kver=$2
case $base in
	saphira-zfs|nvidia-open|saphira-drbd9) ;;
	*) die "unknown kmod family: $base" ;;
esac
case $kver in
	''|*[!0-9.A-Za-z_-]*|*..*) die "invalid kernel version: $kver" ;;
esac

root=${SAPHIRA_RECIPE_ROOT:-/recipes}
new=$root/$base-$kver
[ -e "$new" ] && die "already exists: $new"
[ -f "$root/$base-$kver/recipe.sh" ] 2>/dev/null && die "already exists: $new"

# Nearest template: highest existing variant of the family.
template=""
for dir in "$root"/$base-*/recipe.sh; do
	[ -f "$dir" ] || continue
	suffix=${dir%/recipe.sh}; suffix=${suffix##*/$base-}
	case $suffix in
		''|*[!0-9.A-Za-z_-]*|*..*) continue ;;
	esac
	if [ -z "$template" ]; then
		template=$suffix
	else
		higher=$(printf '%s\n%s\n' "$template" "$suffix" | sort -V | tail -1)
		template=$higher
	fi
done
[ -n "$template" ] || die "no existing variants of $base to copy"
printf 'new-kmod-variant: template %s-%s -> %s-%s\n' "$base" "$template" "$base" "$kver"

cp -r -- "$root/$base-$template" "$new" || die "copy failed"
sed -i \
	-e "s/pkgname=$base-$template/pkgname=$base-$kver/" \
	-e "s/for kernel $template/for kernel $kver/" \
	-e "s/^KVER_SHORT=$template/KVER_SHORT=$kver/" \
	-e "s/saphira-kernel-headers=$template/saphira-kernel-headers=$kver/" \
	"$new/recipe.sh" || die "substitution failed"
grep -q "pkgname=$base-$kver" "$new/recipe.sh" || die "pkgname substitution missed"
grep -q "^KVER_SHORT=$kver" "$new/recipe.sh" || die "KVER_SHORT substitution missed"
grep -q "saphira-kernel-headers=$kver" "$new/recipe.sh" || die "headers pin substitution missed"
case $base in
	nvidia-open)
		[ -f "$new/files/open-gpu-kernel-modules-"*.tar.gz ] ||
			die "nvidia tarball missing in $new/files"
		[ -f "$new/files/"*.patch ] ||
			die "nvidia patch missing in $new/files"
		;;
	*)
		[ -n "$(ls "$new"/files/*.tar.gz 2>/dev/null)" ] ||
			die "source tarball missing in $new/files"
		;;
esac
sh -n "$new/recipe.sh" || die "syntax check failed"
printf 'new-kmod-variant: wrote %s/recipe.sh\n' "$new"
printf 'new-kmod-variant: unlock checklist for %s:\n' "$kver"
printf '  1. kernel tree built on Egg: /usr/src/linux-%s + `make scripts` (else staging skips it)\n' "$kver"
printf '  2. saphira-kernel-headers=%s published (else resolvepkg fails closed)\n' "$kver"
printf '  3. stage + build: build-kmod-set.sh %s-%s\n' "$base" "$kver"

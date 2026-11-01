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
	# The suffix must be a KERNEL VERSION, not merely alphanumeric. The
	# family also contains non-per-kernel packages whose names share the
	# prefix: saphira-zfs-userspace and nvidia-open-firmware. Those passed
	# the old [0-9.A-Za-z_-] test, and sort -V ranks a word above every
	# digit string, so the script cheerfully stamped saphira-zfs-7.2.3 from
	# the USESPACE recipe -- wrong pkgname, wrong depends, no KVER_SHORT, no
	# headers pin. Requiring a leading digit rejects every sibling package
	# and leaves only real per-kernel variants.
	case $suffix in
		''|[!0-9]*|*[!0-9.A-Za-z_-]*|*..*) continue ;;
	esac
	if [ -z "$template" ]; then
		template=$suffix
	else
		higher=$(printf '%s\n%s\n' "$template" "$suffix" | sort -V | tail -1)
		template=$higher
	fi
done
[ -n "$template" ] || die "no existing variants of $base to copy"
# kmod UAPI deps name the single active line bare
# (saphira-linux-uapi-headers, no version pin: there is only ever one
# /usr/include provider, so pinning is meaningless). The copy inherits
# the template's bare reference unchanged; assert it survived.
grep -q "^[[:space:]]*saphira-linux-uapi-headers$" "$root/$base-$template/recipe.sh" ||
	die "template $base-$template has no bare saphira-linux-uapi-headers dep"
printf 'new-kmod-variant: template %s-%s -> %s-%s\n' "$base" "$template" "$base" "$kver"

cp -r -- "$root/$base-$template" "$new" || die "copy failed"
# Validate BEFORE anything is left behind: a failed stamp used to leave a
# half-substituted recipe directory that the next run then picked as
# its own template. On any failure past this point, remove it.
variant_staged=1
variant_cleanup() { [ "${variant_staged:-0}" = 1 ] && rm -rf -- "$new"; }
trap variant_cleanup EXIT
sed -i \
	-e "s/pkgname=$base-$template/pkgname=$base-$kver/" \
	-e "s/for kernel $template/for kernel $kver/" \
	-e "s/^KVER_SHORT=$template/KVER_SHORT=$kver/" \
	"$new/recipe.sh" || die "substitution failed"
grep -q "pkgname=$base-$kver" "$new/recipe.sh" || die "pkgname substitution missed"
grep -q "^KVER_SHORT=$kver" "$new/recipe.sh" || die "KVER_SHORT substitution missed"
grep -q "^[[:space:]]*saphira-linux-uapi-headers$" "$new/recipe.sh" ||
	die "uapi dep missing after copy"
case $base in
	nvidia-open)
		# Do not pattern-match an upstream filename. NVIDIA serves the
		# driver as <version>.tar.gz even though the download URL is
		# open-gpu-kernel-modules-<version>.tar.gz, so an
		# open-gpu-kernel-modules-*.tar.gz glob never matched and the stamp
		# refused a variant whose 27 MB tarball was vendored correctly.
		# What matters is that a tarball rode along WITH its verified
		# sidecar, and that the fbdev patch is present -- the supply-chain
		# rule, not the spelling of the name.
		ntar=$(ls "$new"/files/*.tar.gz 2>/dev/null | head -1)
		[ -n "$ntar" ] || die "nvidia tarball missing in $new/files"
		[ -f "$ntar.sha256" ] ||
			die "nvidia tarball has no verified .sha256 sidecar: $ntar"
		[ -f "$new/files/"*.patch ] ||
			die "nvidia patch missing in $new/files"
		;;
	*)
		[ -n "$(ls "$new"/files/*.tar.gz 2>/dev/null)" ] ||
			die "source tarball missing in $new/files"
		;;
esac
sh -n "$new/recipe.sh" || die "syntax check failed"
variant_staged=0
printf 'new-kmod-variant: wrote %s/recipe.sh\n' "$new"
printf 'new-kmod-variant: unlock checklist for %s:\n' "$kver"
printf '  1. no staging needed: the kmod build prepares its own tree in-worker\n'
printf '     from the kernel recipe inputs (declare KRECIPE in the new recipe;\n'
printf '     config, tarball and policy patches come from that recipe files/,\n'
printf '     never from the builder /boot), else it fails loudly naming what is missing)\n'
printf '  2. saphira-linux-uapi-headers published (else resolvepkg fails closed)\n'
printf '  3. build: build-kmod-set.sh %s-%s\n' "$base" "$kver"

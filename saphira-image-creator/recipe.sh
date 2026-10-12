#!/bin/sh

# r2: ship files/services.d, the package -> init services mapping, so a
# package may declare the service name it provides instead of the image
# builder assuming service-name == package-name. saphira-packager ships
# saphira-build; naming the package in a profile previously enabled nothing,
# silently. The mapping is data beside the profiles (a profile still lists
# only package intentions, per saphira-profiles(5)) and is optional.
pkgname=saphira-image-creator
pkgver=0.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira bootable image creator: BIOS/UEFI x OpenRC/systemd target matrix over the canonical saphira-install assembler'
license='BUSL-1.1'
origin=saphira-image-creator
repo=saphira
url=https://saphira.vm2.uk/

# The creator ORCHESTRATES; it does not assemble. saphira-install owns the
# mounted-target installation and saphira-assemble-rootfs owns the rootfs
# assembly and the identity replay, so those are hard dependencies: the tool
# refuses to substitute its own path when they are absent.
#
# util-linux supplies sfdisk and losetup on the HOST that builds the image.
# e2fsprogs supplies mkfs.ext4. dosfstools supplies mkfs.vfat, which a
# uefi-* target cannot be built without. grub supplies grub-install and
# grub-mkconfig. qemu is optional: it is needed only for a .qcow2 output.
depends="
	saphira-install-tools
	util-linux
	e2fsprogs
	dosfstools
	grub
"
makedepends=""

recipe_build()
{
	# The target matrix and the profiles are DATA, and a data file that
	# names a package which does not exist produces an image that simply
	# fails to install. Every intention in every shipped profile must be a
	# real recipe, checked here rather than at image-build time.
	local f pkg
	for f in "$RECIPE_DIR"/files/profiles/*; do
		awk '
			{ line = $0; sub(/#.*$/, "", line) }
			line ~ /^[[:space:]]*$/ { next }
			{ gsub(/^[ \t]+|[ \t]+$/, "", line); print line }
		' "$f" | while read -r pkg; do
			[ -n "$pkg" ] || continue
			case $pkg in
			*[![:alnum:]._+-]*) continue ;;
			esac
			[ -f "$SAPHIRA_RECIPE_ROOT/$pkg/recipe.sh" ] || {
				echo "ERROR: ${f##*/} names $pkg, which has no recipe" >&2
				exit 1
			}
		done
	done
	# Every target must name a profile that exists and a supported
	# boot/init pair. A matrix row naming a profile that was renamed would
	# otherwise fail only at image-build time.
	local name boot init profile
	while read -r name boot init profile; do
		case $name in ''|'#'*) continue ;; esac
		case $boot in bios|uefi) ;; *) echo "ERROR: target $name has boot=$boot" >&2; exit 1 ;; esac
		case $init in openrc|systemd) ;; *) echo "ERROR: target $name has init=$init" >&2; exit 1 ;; esac
		[ -f "$RECIPE_DIR/files/profiles/$profile" ] || {
			echo "ERROR: target $name names a missing profile: $profile" >&2
			exit 1
		}
	done < "$RECIPE_DIR/files/targets"
	# Shell and man page must be syntactically valid before they ship.
	/bin/sh -n "$RECIPE_DIR/files/saphira-image" || {
		echo "ERROR: saphira-image does not parse" >&2
		return 1
	}
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-image" \
		"$PKGDEST/usr/bin/saphira-image"
	install -D -m 0644 "$RECIPE_DIR/files/targets" \
		"$PKGDEST/usr/share/saphira/image/targets"
	install -d -m 0755 "$PKGDEST/usr/share/saphira/image/profiles"
	for profile in "$RECIPE_DIR"/files/profiles/*; do
		install -m 0644 "$profile" \
			"$PKGDEST/usr/share/saphira/image/profiles/${profile##*/}"
	done
	# Package -> init services mapping. OPTIONAL data: absent means every
	# service is named after its package, which is the normal case. It
	# exists because that assumption is not universal - saphira-packager
	# ships saphira-build - and the assumption failing enabled nothing,
	# silently.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/image/services.d"
	for svc in "$RECIPE_DIR"/files/services.d/*; do
		[ -f "$svc" ] || continue
		install -m 0644 "$svc" \
			"$PKGDEST/usr/share/saphira/image/services.d/${svc##*/}"
	done
	install -D -m 0644 "$RECIPE_DIR/files/saphira-image.8" \
		"$PKGDEST/usr/share/man/man8/saphira-image.8"
	install -D -m 0644 "$RECIPE_DIR/files/licenses/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-image-creator/LICENSE"
	# The tool resolves its data beside itself, so the payload must carry
	# both. Asserted rather than assumed: a missing data file makes every
	# subcommand fail at runtime, which is exactly the class of defect
	# this package exists to remove from the image path.
	for p in usr/share/saphira/image/targets usr/bin/saphira-image; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-image-creator payload is missing $p" >&2
			return 1
		}
	done
	[ -d "$PKGDEST/usr/share/saphira/image/profiles" ] || {
		echo "ERROR: saphira-image-creator shipped no profiles" >&2
		return 1
	}
	# Every declared mapping must be non-empty, or it would silently enable
	# nothing and reintroduce the defect it exists to fix.
	for svc in "$PKGDEST"/usr/share/saphira/image/services.d/*; do
		[ -f "$svc" ] || continue
		[ -s "$svc" ] || {
			echo "ERROR: empty services.d mapping would enable nothing: ${svc##*/}" >&2
			return 1
		}
	done
}

#!/bin/sh

pkgname=saphira-install-tools
pkgver=0.1
pkgrel=12
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira image/install tooling (bootstrap, chroot, genfstab, assembler, installer, imager) and install profiles'
license='BUSL-1.1'
origin=saphira-install-tools
repo=saphira
url=https://saphira.vm2.uk/

# Payload vendored from the live Egg install (the generation-zero Stage4
# mount is retired); bytes pinned below. r1 is the ABI migration:
#   depends: akadata-base-abi -> saphira-base-abi
#   profiles/base: akadata-base-abi -> saphira-base-abi;
#                  grub-common/grub-bios/grub-efi -> grub (monolithic)
#   profiles/server: php85-cli/php85-fpm/php85-opcache/php85-* extensions
#                    -> php85 (single package; extensions return when
#                    libcurl/oniguruma ports land)
depends="
	apk-tools
	coreutils
	saphira-base-abi
	util-linux
"
makedepends=""

recipe_build()
{
	local f
	for f in "$RECIPE_DIR"/files/saphira-* "$RECIPE_DIR"/files/profiles/*; do
		grep -q 'akadata-base-abi' "$f" && {
			echo "ERROR: unmigrated akadata-base-abi reference in $f" >&2
			return 1
		}
	done
	# Byte-pin the vendored payload.
	(cd "$RECIPE_DIR/files" && sha256sum -c files.sha256) || return 1
}

recipe_install()
{
	for tool in saphira-chroot saphira-bootstrap saphira-genfstab saphira-assemble-rootfs saphira-install saphira-image; do
		install -D -m 0755 "$RECIPE_DIR/files/$tool" "$PKGDEST/usr/bin/$tool"
	done
	for profile in base build network server virtualisation-host; do
		install -D -m 0644 "$RECIPE_DIR/files/profiles/$profile" \
			"$PKGDEST/usr/share/saphira/profiles/$profile"
	done
	for sidecar in "$RECIPE_DIR"/files/profiles/*.services; do
		install -D -m 0644 "$sidecar" \
			"$PKGDEST/usr/share/saphira/profiles/$(basename "$sidecar")"
	done
	install -D -m 0644 "$RECIPE_DIR/files/saphira-bootstrap.8" \
		"$PKGDEST/usr/share/man/man8/saphira-bootstrap.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-profiles.5" \
		"$PKGDEST/usr/share/man/man5/saphira-profiles.5"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-assemble-rootfs.8" \
		"$PKGDEST/usr/share/man/man8/saphira-assemble-rootfs.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-install.8" \
		"$PKGDEST/usr/share/man/man8/saphira-install.8"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-image.8" \
		"$PKGDEST/usr/share/man/man8/saphira-image.8"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-install-tools/LICENSE"
}

#!/bin/sh
pkgname=wireguard-tools
pkgver=1.0.20260223
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='WireGuard userspace tools (wg, wg-quick)'
license='GPL-2.0-only'
origin=wireguard-tools
repo=saphira
url=https://www.wireguard.com/
wireguard_tools_sha256=587db136e52a53999bd58df8626137b2600db90909a4020b0f7c8b356ac6799b
depends="bash"
makedepends="saphira-kernel-headers=7.1.5 gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/wireguard-tools-v1.0.20260223.tar.xz"
	cd "$SRC"
	echo "$wireguard_tools_sha256  $RECIPE_DIR/files/wireguard-tools-v1.0.20260223.tar.xz" | sha256sum -c -
	make -C src -j${JOBS:-$(nproc)} \
		WITH_BASHCOMPLETION=yes WITH_SYSTEMDUNITS=no \
		WITH_WGQUICK=yes
}
recipe_install() {
	make -C "$SRC/src" install \
		WITH_BASHCOMPLETION=yes WITH_SYSTEMDUNITS=no \
		WITH_WGQUICK=yes PREFIX=/usr DESTDIR="$PKGDEST"
}

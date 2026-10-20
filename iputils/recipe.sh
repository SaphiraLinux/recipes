#!/bin/sh
pkgname=iputils
pkgver=20250605
pkgrel=3
# r3: caps.d declares cap_net_raw for ping/arping (build sets neither
# setcap nor setuid by policy; without the declaration ordinary
# users cannot ping - proven on firstboot-created accounts).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Network utilities (ping, arping, tracepath, clockdiff)'
license='BSD-3-Clause GPL-2.0-or-later'
origin=iputils
repo=saphira
url=https://github.com/iputils/iputils
iputils_sha256=19e680c9eef8c079da4da37040b5f5453763205b4edfb1e2c114de77908927e4
depends="libcap"
makedepends="saphira-linux-uapi-headers meson ninja gcc pkgconf libcap-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/iputils-20250605.tar.gz"
	cd "$SRC"
	echo "$iputils_sha256  $RECIPE_DIR/files/iputils-20250605.tar.gz" | sha256sum -c -
	meson setup _build --prefix=/usr \
		-DNO_SETCAP_OR_SUID=true \
		-DBUILD_MANS=false \
		-DUSE_IDN=false \
		-DUSE_GETTEXT=false
	meson compile -C _build
}
recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C "$SRC/_build"
	# Raw-socket capabilities for ordinary users (the build sets
	# neither setcap nor setuid by policy): ping/arping without
	# cap_net_raw fail for non-root with a capability error.
	install -D -m 0644 "$RECIPE_DIR/files/caps.d/iputils" \
		"$PKGDEST/usr/share/saphira/caps.d/iputils"
}
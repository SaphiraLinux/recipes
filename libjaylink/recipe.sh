#!/bin/sh
pkgname=libjaylink
pkgver=0.5.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='SEGGER J-Link access library (flashrom J-Link programmer backend)'
license='LGPL-2.1-or-later'
origin=libjaylink
repo=saphira
url=https://gitlab.zapb.de/libjaylink/libjaylink
source=https://gitlab.zapb.de/libjaylink/libjaylink/-/archive/${pkgver}/libjaylink-${pkgver}.tar.gz
sha256=235b12d161b29d813026704f335536a6a916646ea2058302e4ca45ca2cd81325

# USB transport lives in the library itself; udev rules ship alongside
# so J-Link probes are accessible (fuse3 precedent: /lib/udev/rules.d).
# udev-dev is a hard requirement: libusb's .la pulls -ludev into our link.
depends="libusb udev"
# GitLab archive ships no pregenerated configure (m4/ + autogen.sh only).
makedepends="autoconf automake binutils gcc libtool libusb-dev make pkgconf udev-dev"
subpackages="$pkgname-dev"

recipe_build() {
	JAYLINK_BALL="$RECIPE_DIR/files/libjaylink-${pkgver}.tar.gz"
	echo "$sha256  $JAYLINK_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$JAYLINK_BALL"
	cd "$SRC"
	autoreconf -i
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--libdir=/usr/lib --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
	install -D -m 0644 "$SRC/contrib/60-libjaylink.rules" \
		"$PKGDEST/lib/udev/rules.d/60-libjaylink.rules"
}

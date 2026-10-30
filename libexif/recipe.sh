#!/bin/sh

pkgname=libexif
pkgver=0.6.26
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="EXIF metadata parsing library (includes CVE-2026-40386 fix)"
license='LGPL-2.1-or-later'
origin=libexif
repo=saphira
url=https://github.com/libexif/libexif
source=https://github.com/libexif/libexif/releases/download/v0.6.26/libexif-0.6.26.tar.bz2
sha256=0830ed253fceeb60444fb309598bc8a9491d3007dc054aad3a50a347c5597c57

depends=""

makedepends="
    gcc
    make
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/libexif-0.6.26.tar.bz2"
	echo "$sha256  $RECIPE_DIR/files/libexif-0.6.26.tar.bz2" | sha256sum -c -
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --libdir=/usr/lib
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	test -f "$SRC/COPYING" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/libexif/COPYING"
}

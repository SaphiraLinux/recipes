#!/bin/sh

# augeas: configuration editing library (libvirt netcf feature).

pkgname=augeas
pkgver=1.15.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Configuration file editing library"
license="LGPL-2.1-or-later"
origin=augeas
repo=saphira
url=https://github.com/hercules-team/augeas
source=https://github.com/hercules-team/augeas/releases/download/release-${pkgver}/augeas-${pkgver}.tar.gz
sha256=95b2b5c4c10c964024c694d6349024e8033dcfa1aaba88884ea09394908d30ff

# Runtime DT edges (RUNTIME stage proved each): libxml2.so.16 (note
# the 2.14 SONAME, not .so.2), libreadline.so.8 (augtool), libgcc_s.
depends="
    gcc-libs
    libxml2
    readline
"

makedepends="
    binutils
    gcc
    libxml2-dev
    make
    pkgconf
    readline-dev
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/augeas/COPYING"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# versioned .so and the lenses stay in main.
	for p in usr/lib/libaugeas.so usr/include/augeas.h usr/share/augeas/lenses; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: augeas payload is missing $p" >&2
			return 1
		}
	done
}

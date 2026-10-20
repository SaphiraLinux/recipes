#!/bin/sh

# libcap-ng: POSIX capabilities easy-API (libvirt -Dcapng, auditd).
# Utilities (netcap/pscap/filecap) ship as part of upstream.

pkgname=libcap-ng
pkgver=0.8.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="POSIX capabilities programming library and inspection utilities"
license="GPL-2.0-only AND LGPL-2.1-or-later"
origin=libcap-ng
repo=saphira
url=https://people.redhat.com/sgrubb/libcap-ng/
source=https://people.redhat.com/sgrubb/libcap-ng/libcap-ng-${pkgver}.tar.gz
sha256=3ba5294d1cbdfa98afaacfbc00b6af9ed2b83e8a21817185dfd844cc8c7ac6ff

# Python bindings need swig (absent in-tree) and skip themselves with
# a warning -- nothing to disable (feature policy: no binding stack
# without a consumer).
makedepends="
    binutils
    gcc
    make
    pkgconf
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
		"$PKGDEST/usr/share/licenses/libcap-ng/COPYING"
	install -m 0644 "$SRC/COPYING.LIB" \
		"$PKGDEST/usr/share/licenses/libcap-ng/COPYING.LIB"
	# .a/.pc/headers to -dev, man pages to -doc via the fixed split
	# predicates; the versioned .so and the utils stay in main.
	for p in usr/lib/libcap-ng.so usr/include/cap-ng.h usr/share/man; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libcap-ng payload is missing $p" >&2
			return 1
		}
	done
}

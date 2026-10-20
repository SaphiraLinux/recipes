#!/bin/sh

# libiscsi: iSCSI client library (libvirt storage_iscsi_direct).
# The iscsi-* utilities ship as part of upstream.

pkgname=libiscsi
pkgver=1.20.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="iSCSI client library and utilities"
license="GPL-2.0-or-later AND LGPL-2.1-or-later"
origin=libiscsi
repo=saphira
url=https://github.com/sahlberg/libiscsi
source=https://github.com/sahlberg/libiscsi/archive/refs/tags/${pkgver}.tar.gz
sha256=212f6e1fd8e7ddb4b02208aafc6de600f6f330f40359babeefdd83b0c79d47a1

# Git archive: no pregenerated configure (autogen.sh + configure.ac
# only). --disable-werror: upstream develops with -Werror and gcc 16
# trips new warnings. Tests/examples/test-tool need a live iSCSI
# target, unavailable in the build sandbox -- disabled with reason.
makedepends="
    autoconf
    automake
    binutils
    gcc
    libtool
    make
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	autoreconf -fi
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-werror \
		--disable-tests \
		--disable-examples \
		--disable-test-tool
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/LICENCE-GPL-2.txt" \
		"$PKGDEST/usr/share/licenses/libiscsi/LICENCE-GPL-2.txt"
	install -m 0644 "$SRC/LICENCE-LGPL-2.1.txt" \
		"$PKGDEST/usr/share/licenses/libiscsi/LICENCE-LGPL-2.1.txt"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# versioned .so and the iscsi-* utilities stay in main.
	for p in usr/lib/libiscsi.so usr/include/iscsi; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libiscsi payload is missing $p" >&2
			return 1
		}
	done
}

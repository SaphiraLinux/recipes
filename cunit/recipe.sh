#!/bin/sh

# cunit: C unit-test framework. Test-only infrastructure: the sole
# in-tree consumer is libsepol's unit suite (CUnit/Basic.h). No
# runtime package depends on this.

pkgname=cunit
# Upstream versions as 2.1-3; the dash cannot survive apk (it
# separates the pkgrel revision), so the apk-native _p<N> spelling
# carries it (post-release semantics, per recipe-rules). The fetch
# URL keeps the upstream spelling via upstream_ver.
upstream_ver=2.1-3
pkgver=2.1_p3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="C unit testing framework (test-only dependency)"
license="LGPL-2.0-or-later"
origin=cunit
repo=saphira
url=https://cunit.sourceforge.net/
source=https://downloads.sourceforge.net/project/cunit/CUnit/${upstream_ver}/CUnit-${upstream_ver}.tar.bz2
sha256=f5b29137f845bb08b77ec60584fdb728b4e58f1023e6f249a464efa49a40f214

# autoconf/automake/libtool regenerate configure: the release
# tarball ships configure.in plus stale build outputs, no working
# configure. Curses and example interfaces default off upstream.
makedepends="
    autoconf
    automake
    binutils
    gcc
    libtool
    make
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	autoreconf -fi
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
		"$PKGDEST/usr/share/licenses/cunit/COPYING"
	# Headers + static archive travel to -dev via the fixed split
	# predicates; the shared object stays in main.
	for p in usr/lib/libcunit.so usr/include/CUnit; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: cunit payload is missing $p" >&2
			return 1
		}
	done
}

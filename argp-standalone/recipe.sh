pkgname=argp-standalone
pkgver=1.4.1
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Standalone argp argument-parsing library for musl (replaces v0 stub with real payload)'
license='LGPL-2.1-or-later'
origin=argp-standalone
repo=main
url=https://github.com/ericonr/argp-standalone
source=https://github.com/ericonr/argp-standalone/archive/refs/tags/1.4.1.tar.gz
sha256=879d76374424dce051b812f16f43c6d16de8dbaddd76002f83fd1b6e57d39e0b

makedepends="
	autoconf
	automake
	binutils
	gawk
	gcc
	libtool
	m4
	make
"

subpackages="argp-standalone-dev"
recipe_build()
{
	autoreconf -fi
	export CFLAGS="-fPIC ${CFLAGS--O2}"
	./configure --prefix=/usr
	make -j${JOBS:-$(nproc)}
}

# Upstream ships no usable install target (libargp.a + headers are the payload);
# aports-style manual install.
recipe_install()
{
	install -d "$PKGDEST/usr/lib" "$PKGDEST/usr/include"
	install -m 644 "$SRC/libargp.a" "$PKGDEST/usr/lib/libargp.a"
	install -m 644 "$SRC/argp.h" "$PKGDEST/usr/include/argp.h"
	install -m 644 "$SRC/argp-fmtstream.h" "$PKGDEST/usr/include/argp-fmtstream.h"
}

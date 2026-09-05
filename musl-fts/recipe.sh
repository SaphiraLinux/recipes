#!/bin/sh

pkgname=musl-fts
pkgver=1.2.7
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="FTS(3) functions from glibc for musl libc"
license="BSD-3-Clause"
origin=musl-fts
repo=main
url=https://github.com/void-linux/musl-fts
source=https://github.com/void-linux/musl-fts/archive/refs/tags/v1.2.7.tar.gz
sha256=49ae567a96dbab22823d045ffebe0d6b14b9b799925e9ca9274d47d26ff482a6

depends=""
makedepends="
    gcc
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Upstream is autotools-only (bootstrap.sh needs missing autoconf);
	# the library is a single translation unit, so compile directly in
	# the proven argp-standalone style: static archive plus PIC shared.
	cat > config.h <<'EOF'
#define HAVE_DECL_MAX 1
#define HAVE_DECL_UINTMAX_MAX 1
#define HAVE_DIRFD 1
#define HAVE_DIR_DD_FD 1
#define HAVE_DIR_D_FD 1
EOF
	gcc -I. ${CFLAGS--O2} -c "$SRC/fts.c" -o fts.o
	gcc -I. ${CFLAGS--O2} -fPIC -c "$SRC/fts.c" -o fts.pic.o
	ar crD libfts.a fts.o
	ranlib libfts.a
	gcc -shared -Wl,-soname,libfts.so.0 -o libfts.so.0.0.0 fts.pic.o
	ln -sf libfts.so.0.0.0 libfts.so.0
	ln -sf libfts.so.0 libfts.so
}

recipe_install()
{
	install -D -m 0644 libfts.a "$PKGDEST/usr/lib/libfts.a"
	for so in libfts.so.0.0.0 libfts.so.0; do
		install -m 0755 "$so" "$PKGDEST/usr/lib/$so"
	done
	# the unversioned libfts.so symlink is auto-split into -dev by
	# buildpkg-single (usr/lib '*.so' symlinks).
	ln -sf libfts.so.0.0.0 "$PKGDEST/usr/lib/libfts.so"
	install -d -m 0755 "$PKGDEST/usr/include"
	install -m 0644 "$SRC/fts.h" "$PKGDEST/usr/include/fts.h"
}

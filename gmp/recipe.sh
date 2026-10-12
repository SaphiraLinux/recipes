#!/bin/sh

pkgname=gmp
pkgver=6.3.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU multiple precision arithmetic library"
license="LGPL-3.0-or-later GPL-2.0-or-later"
origin=gmp
repo=main
url=https://gmplib.org/
source=https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz
sha256=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898

depends=""

makedepends="
    binutils
    gawk
    gcc
    make
    m4
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Out-of-tree build per the proven v0 recipe, with its documented
	# policy exception AKADATA_POLICY_EXCEPTION=gmp-gnu17-required.
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	CFLAGS="${CFLAGS-} -std=gnu17" "$SRC/configure" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--enable-cxx \
		--enable-shared \
		--enable-static
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	make DESTDIR="$PKGDEST" install
	# FHS non-usrmerged: /bin consumers (coreutils expr) need the runtime
	# SONAME chain in /lib; the dev linker name stays in /usr/lib
	# pointing back (zlib precedent). Verified: across the whole coreutils
	# payload the only DT_NEEDED libs are libc.so and libgmp.so.10.
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libgmp.so.10"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	link="$PKGDEST/usr/lib/libgmp.so"
	if [ -L "$link" ]; then
		target=$(readlink "$link")
		case $target in */*) :;; *) [ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link";; esac
	fi
}

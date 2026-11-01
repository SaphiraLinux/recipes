#!/bin/sh
pkgname=expat
pkgver=2.8.2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XML parser library'
license='MIT'
origin=expat
repo=saphira
url=https://libexpat.github.io/
expat_sha256=ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
# No runtime dependencies. r3 declared depends="gcc-libs", which was wrong:
# the shipped payload -- libexpat.so.1.12.2 and xmlwf -- links only libc.so
# (musl) and libexpat.so.1; readelf -d shows NEEDED libc.so alone for the
# library and NEEDED libexpat.so.1 plus libc.so for xmlwf, so no libgcc_s
# or libstdc++ reference exists anywhere in the package. gcc is needed to
# BUILD it, and makedepends already says so. The unjustified dep installed
# gcc-libs (8,389 KiB) into every minimal image via systemd -> dbus ->
# expat. The efivar r2->r3 fix is the precedent for the same shape.
depends=""
# Stage4 generation shipped a separate libexpat package owning xmlwf, the
# headers and the shared objects. replaces is the apk-tools v3 ownership
# handover: files of the named packages may be taken over on upgrade
# without an overwrite error (solver ignores replaces; it is conflict
# metadata only). All three legacy names are covered: main takes the
# sonames/xmlwf, -dev the headers and -doc the manual pages.
replaces="libexpat libexpat-dev libexpat-doc"
makedepends="gawk gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/expat-2.8.2.tar.gz"
	cd "$SRC"
	echo "$expat_sha256  $RECIPE_DIR/files/expat-2.8.2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-static  --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

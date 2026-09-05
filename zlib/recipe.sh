#!/bin/sh
pkgname=zlib
pkgver=1.3.1
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Compression library implementing the deflate algorithm'
license='Zlib'
origin=zlib
repo=saphira
url=https://zlib.net/
# Vendored: https://zlib.net/fossils/zlib-1.3.1.tar.gz
zlib_sha256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
depends=""
makedepends="gcc make"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/zlib-1.3.1.tar.gz"
	cd "$SRC"
	echo "$zlib_sha256  $RECIPE_DIR/files/zlib-1.3.1.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --libdir=/usr/lib --shared
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	rm -f "$PKGDEST/usr/lib/libz.a"
	# FHS non-usrmerged: /sbin consumers (fsck.cramfs, mkfs.cramfs)
	# need the runtime SONAME chain in /lib; the dev linker name
	# stays in /usr/lib pointing back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libz.so.1"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	link="$PKGDEST/usr/lib/libz.so"
	if [ -L "$link" ]; then
		target=$(readlink "$link")
		case $target in */*) :;; *) [ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link";; esac
	fi
}

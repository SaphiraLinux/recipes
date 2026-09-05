#!/bin/sh
pkgname=readline
pkgver=8.3
pkgrel=7
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU line-editing library'
license='GPL-3.0-or-later'
origin=readline
repo=saphira
url=https://tiswww.case.edu/php/chet/readline/rltop.html
readline_sha256=fe5383204467828cd495ee8d1d3c037a7eba1389c22bc6a041f627976f9061cc
depends="ncurses"
makedepends="gawk gcc make ncurses-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/readline-8.3.tar.gz"
	cd "$SRC"
	echo "$readline_sha256  $RECIPE_DIR/files/readline-8.3.tar.gz" | sha256sum -c -
	LIBS="-lncursesw" AWK=/usr/bin/mawk \
		./configure --prefix=/usr --libdir=/usr/lib \
		--with-curses --disable-static
	# The shared lib must carry its curses dependency: readline's
	# SHLIB link line ignores configure's LIBS, so pass it at make level.
	make -j${JOBS:-$(nproc)} SHLIB_LIBS="-lncursesw"
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install \
		SHLIB_LIBS="-lncursesw"
	rm -f "$PKGDEST/usr/lib/libhistory.a" "$PKGDEST/usr/lib/libreadline.a"
	# FHS non-usrmerged: /sbin consumers (fdisk, sfdisk) need the
	# runtime SONAME chain in /lib; dev linker names stay in
	# /usr/lib pointing back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libreadline.so.8"* "$PKGDEST/usr/lib/libhistory.so.8"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	for dev in libreadline.so libhistory.so; do
		link="$PKGDEST/usr/lib/$dev"
		[ -L "$link" ] || continue
		target=$(readlink "$link")
		case $target in */*) continue;; esac
		[ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link"
	done
}

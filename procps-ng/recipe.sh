#!/bin/sh
pkgname=procps-ng
pkgver=4.0.5
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Utilities for monitoring your system (ps, top, free, vmstat, watch)'
license='GPL-2.0-or-later LGPL-2.0-or-later'
origin=procps-ng
repo=saphira
url=https://gitlab.com/procps-ng/procps
procps_ng_sha256=5ccf2299eea4751f0b76655d793aed3d63d5612fdd316e909e594b2f8e216af8
depends="ncurses"
makedepends="autoconf automake libtool gettext ncurses-dev saphira-kernel-headers=7.1.5 gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/procps-ng-4.0.5.tar.gz"
	cd "$SRC"
	echo "$procps_ng_sha256  $RECIPE_DIR/files/procps-ng-4.0.5.tar.gz" | sha256sum -c -
	./autogen.sh
	# watch.c uses bool/true without stdbool.h under gcc-16/C23-era headers
	CPPFLAGS="${CPPFLAGS-} -include stdbool.h" \
	./configure --prefix=/usr --disable-static --disable-kill \
		--enable-watch8bit --without-systemd --without-systemdsystemunitdir
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" pkglibexecdir=/usr/lib exec_prefix=/usr install
	# FHS non-usrmerged: /bin consumers (ps, top family) need the
	# runtime SONAME chain in /lib; dev linker names stay in
	# /usr/lib pointing back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libproc2.so.1"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	link="$PKGDEST/usr/lib/libproc2.so"
	if [ -L "$link" ]; then
		target=$(readlink "$link")
		case $target in */*) :;; *) [ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link";; esac
	fi
}

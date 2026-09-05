#!/bin/sh

pkgname=inetutils
pkgver=2.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU network utilities (clients and servers)"
license="GPL-3.0-or-later"
origin=inetutils
repo=saphira
url=https://www.gnu.org/software/inetutils/
source=https://ftp.gnu.org/gnu/inetutils/inetutils-2.6.tar.gz
sha256=ccaa256e0d646df7f285ff158a3291f37cd1fc8382f3774d22f7254127635da7

depends="
    ncurses
"

makedepends="
    binutils
    gcc
    make
    ncurses-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	# Clients and servers enabled per feature policy (no --disable-*);
	# PAM stays off (absent from the native universe).  The classic
	# interactive ftp client is enabled EXPLICITLY (default-on upstream,
	# pinned here per policy) so /usr/bin/ftp is a declared contract of
	# this package, never an autodetection accident.
	"$SRC/configure" --prefix=/usr \
		--without-pam --disable-static \
		--enable-ftp
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# Dual-format service package: OpenRC script and systemd unit.
	# telnetd/rlogind/rshd/talkd/tftpd are inetd-spawned; only inetd itself
	# runs standalone.
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system"
	install -m 0755 "$RECIPE_DIR/files/inetd.initd" \
		"$PKGDEST/etc/init.d/inetd"
	install -m 0644 "$RECIPE_DIR/files/inetd.service" \
		"$PKGDEST/usr/lib/systemd/system/inetd.service"
}

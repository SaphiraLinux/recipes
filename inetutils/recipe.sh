#!/bin/sh

pkgname=inetutils
pkgver=2.6
pkgrel=4
# r4: OpenRC-tracked pidfile /run/inetd.pid -> /var/run/inetd.pid
# (flat, root-run, no subdir). No fhs.d fragment by rule: flat tmpfs
# pidfile needs no migration (document-and-leave, unbound
# precedent). Payload change, revision bumps.
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
		--sysconfdir=/etc \
		--localstatedir=/var \
		--without-pam --disable-static \
		--enable-ftp
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# Single-owner rule (sign-apk-repo ownership gate): logger, ping,
	# traceroute and whois are owned by their dedicated packages
	# (util-linux, iputils, traceroute, whois). inetutils must not ship
	# them even though upstream builds them by default - same shape as
	# the tar recipe deleting its bundled rmt copy (cpio owns it).
	rm -f -- "$PKGDEST/usr/bin/logger" "$PKGDEST/usr/bin/ping" \
		"$PKGDEST/usr/bin/traceroute" "$PKGDEST/usr/bin/whois" \
		"$PKGDEST/usr/share/man/man1/whois.1"
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

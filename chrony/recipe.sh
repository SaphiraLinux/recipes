#!/bin/sh

pkgname=chrony
pkgver=4.8
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="NTP client and server"
license="GPL-2.0-or-later"
origin=chrony
repo=main
url=https://chrony-project.org/
# The upstream CDN serves an HTML bot-challenge to this network;
	# the GitLab release archive carries a generated configure and is
	# byte-equivalent source.
	source=https://gitlab.com/chrony/chrony/-/archive/${pkgver}/chrony-${pkgver}.tar.gz
sha256=21ca27feeef5009fbb3e170d0884a5fbcad248826608256a7e3bca43cd7cd1eb

depends=""

makedepends="
    bison
    m4

    binutils
    gcc
    saphira-kernel-headers=7.1.5
    make
"

recipe_build()
{
	# Proven v0 flags: seccomp filter enabled, no NSS/Tomcrypt crypto,
	# no readline (chronyc works fine line-mode). Runs as root unless a
	# chrony user is provisioned; the packaged unit keeps it simple.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--runstatedir=/run \
		--enable-scfilter \
		--without-nss \
		--without-tomcrypt \
		--disable-readline
	make
	# Man pages need asciidoctor (ruby), not yet packaged; defer them
	# alongside the other documentation work rather than fail install.
	sed -i '/doc install/d' Makefile
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$RECIPE_DIR/files/chrony.conf" \
		"$PKGDEST/etc/chrony.conf"
	install -D -m 0644 "$RECIPE_DIR/files/chronyd.service" \
		"$PKGDEST/usr/lib/systemd/system/chronyd.service"
	install -D -m 0755 "$RECIPE_DIR/files/chronyd.initd" \
		"$PKGDEST/etc/init.d/chronyd"
	install -d -m 0750 "$PKGDEST/var/lib/chrony"
}

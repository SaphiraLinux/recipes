#!/bin/sh

# LLDP daemon for link-layer neighbor visibility. Runs as root by
# upstream default; privilege separation to _lldpd is declared and
# configured (--with-privsep-*) so the identity exists from first
# install, with the data directory owned accordingly.

pkgname=lldpd
pkgver=1.0.22
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLDP daemon for link-layer discovery"
license="ISC"
origin=lldpd
repo=saphira
url=https://lldpd.github.io/
source=https://github.com/lldpd/lldpd/releases/download/1.0.22/lldpd-1.0.22.tar.gz
sha256=552baa55118bccbcd1e61c51db438930a36ce04e0abd84c4c0b7b20633ca2b5a

depends="
    libevent
    readline
"

makedepends="
    binutils
    gcc
    libevent-dev
    make
    pkgconf
    readline-dev
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--with-readline --without-xml \
		--with-privsep-user=_lldpd --with-privsep-group=_lldpd
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Runtime identity declaration: _lldpd:124 for privilege
	# separation (matches the configure --with-privsep-* user/group
	# and the default chroot/run directory).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/lldpd" \
		"$PKGDEST/usr/share/saphira/accounts.d/lldpd"
}

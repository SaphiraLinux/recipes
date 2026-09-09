#!/bin/sh

# Knot DNS clients (kdig/khost/knsupdate) without the daemon
# (--disable-daemon): the server role belongs to unbound/dnsmasq,
# which are already supplied. Libraries ship in the main package;
# split them out only if something links libknot directly.

pkgname=knot-dnsutils
pkgver=3.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Knot DNS clients (kdig/khost/knsupdate)"
license="GPL-2.0-or-later"
origin=knot-dnsutils
repo=saphira
url=https://www.knot-dns.cz/
source=https://secure.nic.cz/files/knot-dns/knot-3.6.0.tar.xz
sha256=922894f04a2835131a24c3b3edcbf761273c1b37d3dc4e46d6923ee3856af130

depends="
    gnutls
    libedit
    nettle
"

makedepends="
    binutils
    gcc
    gnutls-dev
    libedit-dev
    make
    nettle-dev
    pkgconf
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-daemon
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

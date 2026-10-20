#!/bin/sh

pkgname=iptables
pkgver=1.8.13
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Netfilter packet filter administration (OpenStack Neutron dependency)"
license='GPL-2.0-or-later'
origin=iptables
repo=saphira
url=https://www.netfilter.org/projects/iptables/
source=https://www.netfilter.org/pub/iptables/iptables-1.8.13.tar.xz
sha256=1afcd33da9e8f913ace6a2126788162e207e26f5d5e29c6573c0e581ffc58b99

depends="
    libmnl
    libnftnl
    libnfnetlink
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    libmnl-dev
    libnftnl-dev
    libnfnetlink-dev
"

# Development files ship in the main package; no -dev split
# (libpng idiom).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc --disable-static \
		--localstatedir=/var --sbindir=/usr/sbin
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

#!/bin/sh

pkgname=ipset
pkgver=7.24
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Netfilter IP set administration (OpenStack Neutron dependency)"
license='GPL-2.0-or-later'
origin=ipset
repo=saphira
url=https://ipset.netfilter.org/
source=http://ipset.netfilter.org/ipset-7.24.tar.bz2
sha256=fbe3424dff222c1cb5e5c34d38b64524b2217ce80226c14fdcbb13b29ea36112

depends="
    libmnl
"

makedepends="
    binutils
    gcc
    make
    pkgconf
    libmnl-dev
"

# Development files ship in the main package; no -dev split
# (libpng idiom).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc --disable-static \
		--localstatedir=/var --sbindir=/usr/sbin --with-kmod=no
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

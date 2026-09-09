#!/bin/sh

# strongSwan IPsec (IKEv1/IKEv2 site-to-site). Modern stack only:
# charon + swanctl/VICI + kernel-netlink/XFRM. stroke is legacy
# compatibility and ships only if something actually requires it
# (nothing does today). No service units this round (documented
# follow-up, same as FRR); charon runs as root per upstream default.

pkgname=strongswan
pkgver=6.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="strongSwan IPsec (IKEv1/IKEv2)"
license="GPL-2.0-or-later"
origin=strongswan
repo=saphira
url=https://www.strongswan.org/
source=https://download.strongswan.org/strongswan-6.1.0.tar.bz2
sha256=fe6c97481298767213cfc2e9a1da29fdd8018d481ff4cb9cf0283099654f20d4

depends="
    openssl
"

makedepends="
    binutils
    bison
    flex
    gcc
    make
    openssl-dev
    pkgconf
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-defaults \
		--enable-charon --enable-ikev1 --enable-ikev2 --enable-nonces \
		--enable-pubkey --enable-openssl --enable-x509 --enable-pem \
		--enable-pkcs1 --enable-kernel-netlink --enable-socket-default \
		--enable-updown --enable-attr --enable-swanctl --enable-vici \
		--enable-constraints --enable-revocation
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

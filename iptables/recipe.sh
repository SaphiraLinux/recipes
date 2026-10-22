#!/bin/sh

pkgname=iptables
pkgver=1.8.13
pkgrel=2
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
	# Saphira is nftables-native: the 7.3 line carries no legacy table
	# modules at all (proven live), and the legacy cores are now unset on
	# every line. Upstream links the bare v4/v6 names at the legacy
	# multiplexer; repoint them at the nft multiplexer so `iptables` means
	# a working backend everywhere. The -legacy suffixed names keep
	# pointing at legacy-multi (explicit opt-in, unchanged).
	for link in iptables iptables-restore iptables-save \
		ip6tables ip6tables-restore ip6tables-save; do
		ln -sf xtables-nft-multi "$PKGDEST/usr/sbin/$link"
	done
	# Proof: the default entry points resolve to the nft multiplexer.
	for link in iptables ip6tables; do
		[ "$(readlink "$PKGDEST/usr/sbin/$link")" = "xtables-nft-multi" ] ||
			{ echo "ERROR: $link does not resolve to nft" >&2; return 1; }
	done
}

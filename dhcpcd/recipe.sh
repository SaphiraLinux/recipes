pkgname=dhcpcd
pkgver=10.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='dhcpcd DHCP/DHCPv6 client with IA_PD delegation (PPP WAN support)'
license=BSD-2-Clause
origin=dhcpcd
repo=saphira
url=https://github.com/NetworkConfiguration/dhcpcd
source=https://github.com/NetworkConfiguration/dhcpcd/releases/download/v10.5.2/dhcpcd-10.5.2.tar.xz
sha256=3e476657fdb6eeb38b277da3a48d0ac0113ecce5858ebdcddff2b629faed52b4

makedepends="
	binutils
	gcc
	make
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --dbdir=/var/lib/dhcpcd
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

pkgname=iw
pkgver=6.17
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='nl80211-based wireless configuration tool'
license=ISC
origin=iw
repo=main
url=https://wireless.wiki.kernel.org/en/users/documentation/iw
source=https://mirrors.edge.kernel.org/pub/software/network/iw/iw-6.17.tar.xz
sha256=7d182e498289ab39b257da6780d562e415377107f50358ee5b55b8cfe40b1e33

depends="libnl"
makedepends="
	binutils
	gcc
	saphira-kernel-headers=7.1.5
	libnl-dev
	make
	pkgconf
"

recipe_build()
{
	make -j${JOBS:-$(nproc)} SBINDIR=/usr/sbin
}

recipe_install()
{
	make SBINDIR=/usr/sbin DESTDIR="$PKGDEST" install
}

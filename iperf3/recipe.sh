pkgname=iperf3
pkgver=3.19.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='IP bandwidth measurement tool'
license='BSD-3-Clause'
origin=iperf3
repo=saphira
url=https://github.com/esnet/iperf
source=https://github.com/esnet/iperf/archive/refs/tags/${pkgver}.tar.gz
sha256=85e480d7fffdcb1368888aaee9d76bcfc211e17c2a6dcb2060b281498f82c97b

depends="openssl"
makedepends="gcc make pkgconf gawk openssl-dev saphira-kernel-headers=7.1.5"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build() {
	./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

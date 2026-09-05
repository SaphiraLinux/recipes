pkgname=gperf
pkgver=3.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Perfect hash function generator'
license='GPL-3.0-or-later'
origin=gperf
repo=saphira
url=https://www.gnu.org/software/gperf/
source=https://ftp.gnu.org/gnu/gperf/gperf-${pkgver}.tar.gz
sha256=fd87e0aba7e43ae054837afd6cd4db03a3f2693deb3619085e6ed9d8d9604ad8

makedepends="gcc make gawk"

recipe_build() {
	./configure --prefix=/usr
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

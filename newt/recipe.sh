pkgname=newt
pkgver=0.52.25
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Text-mode windowing library (whiptail)'
license='LGPL-2.0-or-later'
origin=newt
repo=main
url=https://releases.pagure.org/newt/
source=https://releases.pagure.org/newt/newt-${pkgver}.tar.gz
sha256=ef0ca9ee27850d1a5c863bb7ff9aa08096c9ed312ece9087b30f3a426828de82

depends="slang popt"
makedepends="gcc make popt-dev slang-dev pkgconf"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build() {
	# configure-cache-cmp.patch is applied by the worker from patches/.
	# --enable-nls is a no-op stub on musl (no gettext) but keeps the
	# upstream flags close to the proven akadata build.
	./configure --prefix=/usr --libdir=/usr/lib \
		--without-python --without-tcl --enable-nls
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	# Saphira is not usrmerged: coreutils install lives at /bin/install;
	# newt's po/Makefile hardcodes /usr/bin/install - override it.
	make INSTALL="install" DESTDIR="$PKGDEST" install
}

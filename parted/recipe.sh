pkgname=parted
pkgver=3.7
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU partition editor and library (libparted)'
license='GPL-3.0-or-later'
origin=parted
repo=saphira
url=https://www.gnu.org/software/parted/
source=https://ftp.gnu.org/gnu/parted/parted-${pkgver}.tar.xz
sha256=008de57561a4f3c25a0648e66ed11e7b30be493889b64334a6d70f2c1951ef7b

depends="util-linux"
makedepends="gcc make pkgconf util-linux-dev saphira-kernel-headers=7.1.5"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build() {
	# Lean Saphira build: no NLS (no gettext in the tree), no readline
	# (non-interactive/scripted use only - no readline package exists
	# yet), no device-mapper (no lvm2 in the tree). blkid/uuid come
	# from util-linux.
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--disable-nls \
		--without-readline \
		--disable-device-mapper \
		--disable-rpath
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

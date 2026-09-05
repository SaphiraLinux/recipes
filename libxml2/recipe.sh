pkgname=libxml2
pkgver=2.14.6
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XML parsing library, version 2'
license='MIT'
origin=libxml2
repo=saphira
url=https://gitlab.gnome.org/GNOME/libxml2
source=https://download.gnome.org/sources/libxml2/2.14/libxml2-${pkgver}.tar.xz
sha256=7ce458a0affeb83f0b55f1f4f9e0e55735dbfc1a9de124ee86fb4a66b597203a

depends="zlib"
subpackages="$pkgname-dev $pkgname-doc"
makedepends="gcc make pkgconf zlib-dev gawk"

recipe_build() {
	./configure --prefix=/usr --without-python --without-lzma --without-iconv --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

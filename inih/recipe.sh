pkgname=inih
pkgver=62
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Simple .ini file parser library'
license='BSD-3-Clause'
origin=inih
repo=saphira
url=https://github.com/benhoyt/inih
source=https://github.com/benhoyt/inih/archive/refs/tags/r${pkgver}.tar.gz
sha256=9c15fa751bb8093d042dae1b9f125eb45198c32c6704cd5481ccde460d4f8151

makedepends="gcc meson ninja pkgconf"
subpackages="$pkgname-dev"

recipe_build() {
	meson setup build -Ddistro_install=true --prefix=/usr
	ninja -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" ninja -C build install
	install -Dm0644 "$SRC/LICENSE.txt" \
		"$PKGDEST/usr/share/licenses/$pkgname/LICENSE"
}

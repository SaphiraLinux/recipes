pkgname=efivar
pkgver=39
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='EFI variable library and efivar tool'
license='LGPL-2.1-or-later GPL-2.0-or-later'
origin=efivar
repo=main
url=https://github.com/rhboot/efivar
# Upstream tag archive (the release asset URL 404s upstream):
# https://github.com/rhboot/efivar/archive/refs/tags/39.tar.gz
source=https://github.com/rhboot/efivar/archive/refs/tags/${pkgver}.tar.gz
sha256=c9edd15f2eeeea63232f3e669a48e992c7be9aff57ee22672ac31f5eca1609a6

depends="gcc-libs"
makedepends="gcc make"
subpackages="$pkgname-dev"

recipe_build() {
	# no-march-native.patch (worker-applied) keeps -march=native out of
	# the ABI; HOST_MARCH= matches the proven akadata build decision.
	make -C "$SRC" -j${JOBS:-$(nproc)} libdir=/usr/lib HOST_MARCH= ENABLE_DOCS=0
}

recipe_install() {
	make -C "$SRC" libdir=/usr/lib HOST_MARCH= ENABLE_DOCS=0 \
		DESTDIR="$PKGDEST" install
	rm -rf "$PKGDEST/usr/share/man" "$PKGDEST/usr/share/doc" \
		"$PKGDEST/usr/share/info"
}

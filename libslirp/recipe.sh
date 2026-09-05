pkgname=libslirp
pkgver=4.9.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='User-mode networking library (QEMU slirp backend)'
license='BSD-3-Clause'
origin=libslirp
repo=saphira
url=https://gitlab.freedesktop.org/slirp/libslirp
# Vendored: https://github.com/qemu/libslirp/archive/refs/tags/v4.9.0.tar.gz
libslirp_sha256=f3bd780f88472fea86e53c62b14120c93f4923bd4836ef33ffa878525ecb8f5b

makedepends="
	binutils
	gcc
	saphira-kernel-headers=7.1.5
	meson
	ninja
	pkgconf
	glib-dev
"

recipe_build()
{
	LSBALL="$RECIPE_DIR/files/libslirp-4.9.0.tar.gz"
	echo "$libslirp_sha256  $LSBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LSBALL"
	meson setup build "$SRC" --prefix=/usr
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
}

pkgname=libpciaccess
pkgver=0.18.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Generic PCI access library (libvirt nodedev driver)'
license='MIT'
origin=libpciaccess
repo=main
url=https://gitlab.freedesktop.org/xorg/lib/libpciaccess
# Vendored: https://www.x.org/archive/individual/lib/libpciaccess-0.18.1.tar.xz
libpciaccess_sha256=4af43444b38adb5545d0ed1c2ce46d9608cc47b31c2387fc5181656765a6fa76

makedepends="
	binutils
	gcc
	make
	meson
	ninja
	pkgconf
"

recipe_build()
{
	PCBALL="$RECIPE_DIR/files/libpciaccess-0.18.1.tar.xz"
	echo "$libpciaccess_sha256  $PCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$PCBALL"
	meson setup build "$SRC" --prefix=/usr -Dzlib=disabled
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
}

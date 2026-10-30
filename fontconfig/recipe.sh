#!/bin/sh

pkgname=fontconfig
pkgver=2.17.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Library for configuring and customizing font access (headless font discovery)'
license='MIT'
origin=fontconfig
repo=saphira
url=https://www.fontconfig.org/
source=https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.17.1/fontconfig-2.17.1.tar.xz
sha256=9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541

depends="
    expat
    freetype
"

makedepends="
    binutils
    bzip2-dev
    gcc
    gettext-dev
    gperf
    make
    pkgconf
    expat-dev
    freetype
    libpng
    util-linux-dev
    zlib-dev
"

subpackages="$pkgname-dev $pkgname-doc"

# No X, no GUI: font discovery and rasterisation support only
# (headless Java and text rendering). NLS stays (gettext is in the
# universe); docs stay off (doc toolchain not needed for the library).
# The system font cache is rebuilt by maintainer hooks after the
# payload lands (ca-certificates precedent): a stale cache would
# describe the previous library/config.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var --disable-static \
		--disable-docs --with-cache-dir=/var/cache/fontconfig
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-fc-cache" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-fc-cache" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
}

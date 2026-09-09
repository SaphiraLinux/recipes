pkgname=libxslt
pkgver=1.1.43
# r3: -dev carries libxml2-dev (libxslt headers include libxml2
# headers; without it every consumer configure fails its libxslt
# probe despite libxslt-dev being installed - proven by the retained
# /build/nginx.buildpkg log, nginx 1.30.4-r4 configure).
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XSLT processing library + xsltproc (libvirt build dependency)'
license='MIT'
origin=libxslt
repo=saphira
url=https://gitlab.gnome.org/GNOME/libxslt
# Vendored: https://github.com/GNOME/libxslt/archive/refs/tags/v1.1.43.tar.gz
libxslt_sha256=e491bb8f11bd43c5da323c66f696b6e7b59d767c446053a7cbd8e805256bd9cb

depends="libxml2"
# Alpine-style -dev dependency: consumers compiling against our
# headers need libxml2 headers too (see r3 note above).
depends_dev="libxml2-dev"
makedepends="
	binutils
	autoconf
	gawk
	automake
	gcc
	libtool
	libxml2-dev
	make
	pkgconf
	zlib-dev
"

subpackages="libxslt-dev libxslt-doc"
recipe_build()
{
	LXBALL="$RECIPE_DIR/files/libxslt-1.1.43.tar.gz"
	echo "$libxslt_sha256  $LXBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LXBALL"
	autoreconf -fi
	./configure --prefix=/usr --without-python --without-crypto --without-debug
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

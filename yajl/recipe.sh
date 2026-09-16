#!/bin/sh

# YAJL (Yet Another JSON Library) 2.1.0.
#
# Ported from /cports guidance (same version, same ISC licence, same
# cmake build). First link of the WAF closure: modsecurity v3
# mandates YAJL (JSON logging; --with-yajl=no disables it and the
# build is then useless for CRS audit logging), so yajl lands first:
#   yajl -> modsecurity -> nginx-mod-modsecurity ; owasp-crs (data)
# Only /usr consumers exist, so no /lib move (runtime-placement rule).

pkgname=yajl
pkgver=2.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Yet Another JSON Library"
license=ISC
origin=yajl
repo=saphira
url=https://github.com/lloyd/yajl
source=https://github.com/lloyd/yajl/archive/refs/tags/2.1.0.tar.gz
sha256=3fb73364a5a30efe615046d07e6db9d09fd2b41c763c5f7d3bfb121cd5c5ac5a

depends="musl"
makedepends="
    binutils
    cmake
    gcc
    make
    ninja
    pkgconf
"
subpackages="$pkgname-dev"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/2.1.0.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/2.1.0.tar.gz" | sha256sum -c -
	cd "$SRC"
	# CMake 4 removed reading the LOCATION target property (the
	# copy-the-tool POST_BUILD steps); use the generator expression
	# the error message prescribes (behavior identical).
	patch -p1 < "$RECIPE_DIR/files/cmake4-target-file.patch"
	# CMake 4 dropped compatibility with the 2.8-era floor pinned
	# in yajl's CMakeLists (minimum-required 2.8.x): pass the
	# documented escape hatch rather than patching upstream's
	# floor (Arch carries the same flag for this tree).
	cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	cmake --build build -j${JOBS:-$(nproc)}
}

recipe_install()
{
	# DESTDIR (exported by the builder) stages the /usr-prefixed
	# install; never pass --prefix here or PKGDEST doubles up.
	DESTDIR="$PKGDEST" cmake --install "$SRC/build"
	test -f "$PKGDEST/usr/lib/libyajl.so.2" ||
		{ echo "ERROR: libyajl.so.2 missing from payload" >&2; return 1; }
	test -f "$PKGDEST/usr/include/yajl/yajl_parse.h" ||
		{ echo "ERROR: yajl headers missing from payload" >&2; return 1; }
}

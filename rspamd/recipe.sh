#!/bin/sh

pkgname=rspamd
pkgver=4.1.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Rapid spam filtering system"
license="Apache-2.0"
origin=rspamd
repo=main
url=https://rspamd.com/
source=https://github.com/rspamd/rspamd/archive/refs/tags/${pkgver}.tar.gz
sha256=e54f2440e7b86ace0ff7d2c37ce4fc3d58bf8a7e5f77099f4d3a5b0bc52a2972

depends="
    glib
    openssl
    pcre2
    xxhash
"

makedepends="
    cmake
    gcc
    glib-dev
    lua54-dev
    icu-dev
    libarchive-dev
    libsodium-dev
    ninja
    openssl-dev
    zlib-dev
    pcre2-dev
    pkgconf
    sqlite-dev
    ragel
    perl
    xxhash-dev
"

subpackages="
    $pkgname-doc
"

recipe_build()
{
	cmake -G Ninja -S "$SRC" -B build \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DCONFDIR=/etc/rspamd \
		-DRUNDIR=/run/rspamd \
		-DDBDIR=/var/lib/rspamd \
		-DLOGDIR=/var/log/rspamd \
		-DRSPAMD_USER=rspamd \
		-DENABLE_LUAJIT=OFF \
		-DENABLE_HYPERSCAN=OFF \
		-DENABLE_SNOWBALL=ON \
		-DENABLE_BACKWARD=OFF \
		-DENABLE_JEMALLOC=OFF \
		-DSYSTEM_XXHASH=ON \
		-DWANT_SYSTEMD_UNITS=OFF \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}"
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system" \
		"$PKGDEST/etc/rspamd/local.d" \
		"$PKGDEST/var/lib/rspamd" "$PKGDEST/var/log/rspamd"
	install -m 0644 "$RECIPE_DIR/files/rspamd.service" \
		"$PKGDEST/usr/lib/systemd/system/rspamd.service"
	install -m 0755 "$RECIPE_DIR/files/rspamd.initd" \
		"$PKGDEST/etc/init.d/rspamd"
	install -m 0644 "$RECIPE_DIR/files/worker-normal.inc" \
		"$PKGDEST/etc/rspamd/local.d/worker-normal.inc"
}

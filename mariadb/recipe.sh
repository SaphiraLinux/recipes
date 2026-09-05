#!/bin/sh
# Port of stage4 mariadb (one unit: mariadb-client/-dev/-doc/-server).
# Runtime splits are separate recipes: mariadb (client) and mariadb-server.
# mariadb-dev / mariadb-doc come from this recipe via subpackages.

pkgname=mariadb
pkgver=11.8.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="MariaDB client programs, client library and tools"
license="GPL-2.0-or-later"
origin=mariadb
repo=saphira
url=https://mariadb.org/
source=https://archive.mariadb.org/mariadb-11.8.8/source/mariadb-11.8.8.tar.gz
sha256=bd023a4959faf012db7f0ebfc0d276729e67e5443df193163f98d80fdfc524c9

depends="
    bzip2
    ca-certificates
    lz4
    lzo
    ncurses
    openssl
    pcre2
    xz
    zlib
"

makedepends="
    binutils
    bison
    m4
    bzip2-dev
    cmake
    fmt-dev
    gcc
    libaio-dev
    lz4-dev
    lzo-dev
    make
    ncurses-dev
    openssl-dev
    pcre2-dev
    pkgconf
    xz-dev
    zlib-dev
"

subpackages="mariadb-dev mariadb-doc"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DINSTALL_LAYOUT=RPM \
		-DINSTALL_SYSCONFDIR=/etc \
		-DINSTALL_LIBDIR=lib \
		-DINSTALL_PLUGINDIR=lib/mysql/plugin \
		-DWITH_SSL=system -DWITH_ZLIB=system -DWITH_PCRE=system \
		-DWITH_UNIT_TESTS=OFF -DWITH_EMBEDDED_SERVER=OFF \
		-DWITH_MARIABACKUP=OFF -DWITH_SYSTEMD=no -DWITH_LIBFMT=system \
		-DWITH_INNODB_BZIP2=ON -DWITH_INNODB_LZ4=ON \
		-DWITH_INNODB_LZMA=ON -DWITH_INNODB_LZO=ON \
		-DWITH_INNODB_SNAPPY=ON \
		-DWITH_WSREP=OFF -DPLUGIN_ROCKSDB=NO -DPLUGIN_MROONGA=NO \
		-DPLUGIN_OQGRAPH=NO -DPLUGIN_CONNECT=NO -DPLUGIN_SPIDER=NO \
		-DCMAKE_C_FLAGS="${CFLAGS-} -fpermissive" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-} -fpermissive" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}"
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	rm -rf "$PKGDEST/usr/lib/systemd"
	rm -f "$PKGDEST/etc/init.d/mysql"
	install -D -m 0644 "$RECIPE_DIR/files/my.cnf" \
		"$PKGDEST/etc/my.cnf"
	install -D -m 0644 "$RECIPE_DIR/files/client.cnf" \
		"$PKGDEST/etc/my.cnf.d/client.cnf"
}

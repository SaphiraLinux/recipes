#!/bin/sh
# Port of stage4 mariadb: server split (mariadbd, install/upgrade tools,
# init script, server config). Shares the mariadb-11.8.8 source pin with
# the mariadb (client) recipe.

pkgname=mariadb-server
pkgver=11.8.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="MariaDB database server"
license="GPL-2.0-or-later"
origin=mariadb-server
repo=saphira
url=https://mariadb.org/
source=https://archive.mariadb.org/mariadb-11.8.8/source/mariadb-11.8.8.tar.gz
sha256=bd023a4959faf012db7f0ebfc0d276729e67e5443df193163f98d80fdfc524c9

depends="
    libaio
    mariadb
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

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DINSTALL_LAYOUT=RPM \
		-DINSTALL_SYSCONFDIR=/etc \
		-DINSTALL_LIBDIR=lib \
		-DINSTALL_PKGCONFIGDIR=lib/pkgconfig \
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
	# Keep only the stage4 mariadb-server payload; the client, -dev and
	# -doc content ships from the mariadb recipe.
	saved=$BUILDDIR/server-split
	install -d "$saved/usr/bin" "$saved/usr/sbin"
	mv "$PKGDEST/usr/sbin/mariadbd" "$saved/usr/sbin/"
	for command in mariadb-install-db mariadb-upgrade; do
		test ! -e "$PKGDEST/usr/bin/$command" || \
			mv "$PKGDEST/usr/bin/$command" "$saved/usr/bin/"
	done
	rm -rf "$PKGDEST"/*
	install -d "$PKGDEST/usr/bin" "$PKGDEST/usr/sbin"
	mv "$saved/usr/sbin/mariadbd" "$PKGDEST/usr/sbin/"
	mv "$saved"/usr/bin/* "$PKGDEST/usr/bin/"
	install -D -m 0644 "$RECIPE_DIR/files/server.cnf" \
		"$PKGDEST/etc/my.cnf.d/server.cnf"
	install -D -m 0755 "$RECIPE_DIR/files/mariadb.initd" \
		"$PKGDEST/etc/init.d/mariadb"
	install -D -m 0644 "$RECIPE_DIR/files/mariadb.service" \
		"$PKGDEST/usr/lib/systemd/system/mariadb.service"
	install -d -m 0750 "$PKGDEST/var/lib/mysql" \
		"$PKGDEST/var/log/mysql"
}

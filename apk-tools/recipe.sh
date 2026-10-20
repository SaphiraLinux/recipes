#!/bin/sh
pkgname=apk-tools
pkgver=3.0.5
# r3: own the apk logrotate fragment (migrated out of the logrotate
# package per the logrotate.d convention; plain rename is correct,
# apk never holds the log open across invocations).
# r4: own the libzstd runtime dependency (libapk.so links libzstd;
# zstd-dev was already a makedepend, so every build linked it while
# no closure ever installed it - proven by a 0.2.1 guest whose apk
# died at exec with libzstd.so.1 missing).
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Alpine/saphira package manager (apk-tools 3) - Genesis base'
license='GPL-2.0-or-later'
origin=apk-tools
repo=saphira
url=https://gitlab.alpinelinux.org/alpine/apk-tools
apk_tools_sha256=8795712ce02457d29c0beb18f82851b408d1d47f98a0cbbbd33ab5ea496f665d
depends="openssl zlib zstd"
makedepends="
	gcc
	saphira-linux-uapi-headers
	make
	meson
	ninja
	cmake
	openssl-dev
	lua54-dev
	scdoc
	pkgconf
	python3
	zlib-dev
	zstd-dev
"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/apk-tools-3.0.5.tar.gz"
	cd "$SRC"
	echo "$apk_tools_sha256  $RECIPE_DIR/files/apk-tools-3.0.5.tar.gz" | sha256sum -c -
	meson setup build . \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dlua=enabled \
		-Dlua_version=5.4 \
		-Dlua_pc=lua54 \
		-Dlua_bin=lua54 \
		-Ddocs=enabled \
		-Dtests=disabled
	meson compile -C build
}
recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/apk" \
		"$PKGDEST/etc/logrotate.d/apk"
}

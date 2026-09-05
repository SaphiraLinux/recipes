#!/bin/sh
pkgname=cronie
pkgver=1.7.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Standard cron daemon with anacron support'
license='MIT BSD-2-Clause'
origin=cronie
repo=saphira
url=https://github.com/cronie-crond/cronie
cronie_sha256=241ecc1dcd8d4b2a6744fe93509932254d20b7bb9d979d27429809493806357f
depends=""
makedepends="autoconf automake gcc make saphira-kernel-headers=7.1.5"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/cronie-1.7.2.tar.gz"
	cd "$SRC"
	echo "$cronie_sha256  $RECIPE_DIR/files/cronie-1.7.2.tar.gz" | sha256sum -c -
	autoreconf -fi "$SRC"
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0001-load_entry-error_func-prototype-c23.patch"
	# gcc16/C23 makes incompatible-pointer-types an error; cronie 1.7.2
	# passes mismatched fn pointers to load_entry
	CFLAGS="${CFLAGS-} -Wno-incompatible-pointer-types -Wno-error=incompatible-pointer-types -Wno-error=declaration-missing-parameter-type" ./configure --prefix=/usr \
		--without-pam --without-selinux --without-audit \
		--with-inotify --enable-anacron \
		--without-systemd
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

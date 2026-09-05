#!/bin/sh

pkgname=rsync
pkgver=3.4.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Fast incremental file transfer utility'
license='GPL-3.0-or-later'
origin=rsync
repo=saphira
url=https://rsync.samba.org/
source=https://download.samba.org/pub/rsync/src/rsync-${pkgver}.tar.gz
sha256=2924bcb3a1ed8b551fc101f740b9f0fe0a202b115027647cf69850d65fd88c52

makedepends="gcc make pkgconf"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --disable-md2man --disable-simd \
		--disable-openssl --disable-xxhash --disable-zstd --disable-lz4
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

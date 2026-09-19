#!/bin/sh

pkgname=rsync
pkgver=3.5.0
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Fast incremental file transfer utility'
license='GPL-3.0-or-later'
origin=rsync
repo=saphira
url=https://rsync.samba.org/
source=https://download.samba.org/pub/rsync/src/rsync-${pkgver}.tar.gz
sha256=c7ffd1ef653e99540f661e47cb00b7f9cad1ee6b972399b16f93d672656e0d33

# r3: declare the runtime libraries rsync links (r2 shipped with an
# empty depends=, so installs missed liblz4/libxxhash and broke; and it
# was built without acl-dev present, hence "no ACLs"). Features are
# explicit, not autodetected: ACL + xattr + xxhash + zstd + lz4 +
# openssl all on.
# r4: own the rsyncd logrotate fragment (migrated out of the
# logrotate package per the logrotate.d convention; applies to
# rsync daemon mode, which holds its log open: copytruncate).
depends="acl attr lz4 openssl xxhash zlib zstd"
makedepends="
    acl-dev
    attr-dev
    gcc
    make
    openssl-dev
    pkgconf
    xxhash-dev
    zstd-dev
    lz4-dev
"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--enable-acl-support \
		--enable-xattr-support \
		--enable-xxhash \
		--enable-zstd \
		--enable-lz4 \
		--enable-openssl
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/rsyncd" \
		"$PKGDEST/etc/logrotate.d/rsyncd"
}

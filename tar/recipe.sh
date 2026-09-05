#!/bin/sh

pkgname=tar
pkgver=1.35
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU tar archiver (Genesis base, acl closure declared)'
license='GPL-3.0-or-later'
origin=tar
repo=saphira
url=https://www.gnu.org/software/tar/
# Vendored: https://ftp.gnu.org/gnu/tar/tar-1.35.tar.xz
tar_sha256=4d62ff37342ec7aed748535323930c7cf94acf71c3591882b26a7ea50f3edc16

depends="acl attr"
makedepends="
	acl-dev
	gawk
	attr-dev
	gcc
	make
"

# GNU cpio owns /usr/libexec/rmt and man8/rmt.8: both upstreams ship the
# same paxutils rmt, and the v0 reference tar recipe deleted tar's copy
# post-install. --with-rmt=FILE is the upstream-supported opt-out ("Do not
# build included copy of rmt"): tar installs neither rmt nor rmt.8 and uses
# the cpio-installed one via DEFAULT_RMT_COMMAND.
recipe_build()
{
	TRBALL="$RECIPE_DIR/files/tar-1.35.tar.xz"
	echo "$tar_sha256  $TRBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$TRBALL"
	cd "$SRC"
	export FORCE_UNSAFE_CONFIGURE=1
	./configure --prefix=/usr --disable-nls --with-rmt=/usr/libexec/rmt
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

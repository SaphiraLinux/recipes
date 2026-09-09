#!/bin/sh

pkgname=rpcsvc-proto
pkgver=1.4.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="XDR/RPC protocol headers and rpcgen (SunRPC toolchain)"
license="BSD-3-Clause"
origin=rpcsvc-proto
repo=main
url=https://github.com/thkukuk/rpcsvc-proto
# rpcgen is a hard configure requirement of glusterfs and is no longer
# shipped by libtirpc; the headers ride with libtirpc at runtime.
vendor=https://github.com/thkukuk/rpcsvc-proto/releases/download/v1.4.4/rpcsvc-proto-1.4.4.tar.xz
sha256=81c3aa27edb5d8a18ef027081ebb984234d5b5860c65bd99d4ac8f03145a558b

depends=""

makedepends="
    autoconf
    automake
    gcc
    make
"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE (see
	# the gpsd recipe comment for why the re-extract is harmless).
	RPCBALL="$RECIPE_DIR/files/rpcsvc-proto-1.4.4.tar.xz"
	if [ -f "$RPCBALL" ]; then
		echo "$sha256  $RPCBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local rpcsvc-proto-1.4.4.tar.xz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		RPCBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RPCBALL"
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

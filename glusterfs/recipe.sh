#!/bin/sh

pkgname=glusterfs
pkgver=11.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GlusterFS distributed filesystem (glusterd, bricks, FUSE client, CLI)"
license="GPL-2.0-only OR LGPL-3.0-or-later"
origin=glusterfs
repo=main
url=https://www.gluster.org/
# download.gluster.org tops out at 11.1; the Debian .orig.tar.gz is the
# byte-identical upstream 11.2 dist tarball - the hash below was
# cross-checked against the 11.2-5 .dsc Checksums-Sha256 before pinning.
# NOTE: no prebuilt configure in the dist tarball; autogen.sh runs at
# build time (autoconf/automake/libtool below).
vendor=https://deb.debian.org/debian/pool/main/g/glusterfs/glusterfs_11.2.orig.tar.gz
sha256=540683ab1acdc95c7fe940061fb24464e1d3d0955a8610d79376911b73ed4ce4

# Runtime: userspace-rcu (librcu), libuuid (util-linux), libfuse3 (mount path),
# libxml2 (mgmt/geo-rep output), libtirpc (transport), openssl, acl,
# zlib, curl (cloudsync S3 plugin, auto-detected - declared explicit),
# python3 (glusterd helpers, CLI tooling, events, geo-rep).
depends="
    acl
    curl
    fuse3
    libtirpc
    libxml2
    openssl
    python3
    userspace-rcu
    util-linux
    zlib
"

makedepends="
    acl-dev
    argp-standalone-dev
    autoconf
    automake
    bison
    curl-dev
    flex
    fuse3-dev
    gcc
    libtirpc-dev
    libtool
    libxml2-dev
    make
    openssl-dev
    pkgconf
    python3
    rpcsvc-proto
    userspace-rcu-dev
    util-linux-dev
    zlib-dev
"

# No tcmalloc packaged (upstream defaults it on - must opt out or
# configure hard-fails); no SELinux on Saphira; no systemd units (the
# USE_SYSTEMD conditional keys off /usr/lib/systemd/system, absent in
# the sandbox - OpenRC scripts ship in files/ instead). Upstream sysv
# init scripts are parked out of /etc/init.d; ours take their place.
# Everything else at upstream defaults: geo-replication, events, fuse
# client + notifications, libxml2 output, OCF agents, C++ gfapi.
gluster_options="
    --prefix=/usr
    --sysconfdir=/etc
    --localstatedir=/var
    --with-mountutildir=/sbin
    --with-initdir=/usr/share/glusterfs/init.d
    --without-tcmalloc
    --disable-selinux
"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE (see
	# the gpsd recipe comment for why the re-extract is harmless).
	GLBALL="$RECIPE_DIR/files/glusterfs_11.2.orig.tar.gz"
	if [ -f "$GLBALL" ]; then
		echo "$sha256  $GLBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local glusterfs_11.2.orig.tar.gz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		GLBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GLBALL"
	cd "$SRC"
	./autogen.sh
	./configure $gluster_options
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0755 "$RECIPE_DIR/files/glusterd.initd" \
		"$PKGDEST/etc/init.d/glusterd"
	install -D -m 0755 "$RECIPE_DIR/files/glustereventsd.initd" \
		"$PKGDEST/etc/init.d/glustereventsd"
}

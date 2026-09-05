pkgname=libtirpc
pkgver=1.3.7
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Transport-Independent RPC library (musl-compatible build)'
license=BSD-3-Clause
origin=libtirpc
repo=main
url=https://git.linux-nfs.org/?p=steved/libtirpc.git
# Upstream git-host snapshots are generated on the fly (non-reproducible
# bytes), so the verified salsa.debian.org archive is vendored in files/.
# Vendored source: https://salsa.debian.org/debian/libtirpc/-/archive/upstream/1.3.7/libtirpc-upstream-1.3.7.tar.gz
libtirpc_sha256=7aeceb70f8d3771fb77cde24eacf3756b302389ce84d0de5209c16e3aedf7cf2

depends=""

subpackages="$pkgname-dev"

makedepends="
    binutils
    gcc
    gawk
    saphira-kernel-headers=7.1.5
    make
    pkgconf
"

recipe_build()
{
	SRCBALL="$RECIPE_DIR/files/libtirpc-upstream-1.3.7.tar.gz"
	echo "$libtirpc_sha256  $SRCBALL" | sha256sum -c -
	tar -C "$SRC" --strip-components=1 -xf "$SRCBALL"
	cp -r "$RECIPE_DIR/files/queue-compat" "$SRC/compat"
	# --enable-rpcdb: compiles src/getrpcent.c (getrpcbynumber and
	# friends, a self-contained /etc/rpc parser). Without it the
	# symbols are absent from the library and ONC RPC consumers fail
	# at link time - rpcbind's security.c needs getrpcbynumber, and
	# musl libc does not provide the getrpcent family itself. The
	# upstream default is off because glibc libc has the functions
	# built in; musl needs the libtirpc implementation.
	./configure --prefix=/usr --sysconfdir=/etc --disable-gssapi --disable-static \
		--disable-dependency-tracking --enable-rpcdb
	make -j${JOBS:-$(nproc)} CPPFLAGS="-I$SRC/compat"
}

recipe_install()
{
	make CPPFLAGS="-I$SRC/compat" DESTDIR="$PKGDEST" install
}

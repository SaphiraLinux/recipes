#!/bin/sh

pkgname=libssh
pkgver=0.12.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='SSH client library (QEMU ssh:// block backend, SFTP, server support)'
license='LGPL-2.1-or-later'
origin=libssh
repo=saphira
url=https://www.libssh.org/
source=https://www.libssh.org/files/0.12/libssh-0.12.2.tar.xz
sha256=49560f677d96e3706a904ac2de1116e25f3680937d51e5c92198fcba4a1c1e9f

depends="openssl zlib"
makedepends="
	binutils
	cmake
	doxygen
	doxygen-awesome-css
	gcc
	make
	ninja
	openssl-dev
	pkgconf
	zlib-dev
"

subpackages="$pkgname-dev $pkgname-doc"

# API docs are built with the packaged doxygen into the -doc split
# (upstream provides doxygen sources, not man pages). The awesome-css
# theme comes from the in-tree doxygen-awesome-css package via
# -DDOXYGEN_AWESOME_CSS_DIR, so the docs build never downloads the
# theme at build time (upstream default fetches a tarball).
# doxygen awesome extensions need no graphviz dot for C API docs
# (DOXYGEN_HAVE_DOT is off upstream: "not relevant for C projects").

# OpenSSL crypto backend (upstream default; GCRYPT/MBEDTLS stay off).
# SFTP stays on (QEMU ssh:// block driver uses the sftp subsystem).
# GSSAPI off (no krb5 in tree; non-required probe would auto-disable
# anyway - explicit is deterministic). Examples off (dev samples, not
# shipped). Tests off (needs cmocka/openssh/dropbear). PCAP off
# (packet-debugging dev feature, not a VM capability). Server support
# stays at upstream default (same lib, no separate daemon). WITH_EXEC
# stays at upstream default (documented upstream behaviour for
# match-exec/proxyjump config handling - not silently changed).
recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DWITH_GSSAPI=OFF \
		-DWITH_EXAMPLES=OFF \
		-DWITH_PCAP=OFF \
		-DUNIT_TESTING=OFF \
		-DCLIENT_TESTING=OFF \
		-DSERVER_TESTING=OFF \
		-DDOXYGEN_AWESOME_CSS_DIR=/usr/share/doxygen-awesome-css \
		-DDOXYGEN_OUTPUT_DIRECTORY="$BUILDDIR/apidocs"
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
	cmake --build "$BUILDDIR" --target docs
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	rm -f "$PKGDEST"/usr/lib/libssh*.a
	# Upstream installs no docs payload; stage the doxygen HTML output
	# for the -doc split (fail closed if the docs target produced
	# nothing - a silent empty -doc would hide a broken docs build).
	ls "$BUILDDIR"/apidocs/html/index.html >/dev/null 2>&1 || { echo "ERROR: libssh docs build produced no apidocs/html/index.html" >&2; return 1; }
	install -d "$PKGDEST/usr/share/doc/libssh"
	cp -a "$BUILDDIR"/apidocs/html "$PKGDEST/usr/share/doc/libssh/html"
}

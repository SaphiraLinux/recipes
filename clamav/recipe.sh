#!/bin/sh

pkgname=clamav
pkgver=1.5.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ClamAV antivirus engine: libraries and scanner utilities"
license="GPL-2.0-or-later"
origin=clamav
repo=main
url=https://www.clamav.net/
# Official tarball carries the vendored Rust crates (.cargo/vendor);
# GitHub tag archives do not and cargo would need network access.
source=https://www.clamav.net/downloads/production/clamav-1.5.3.tar.gz
sha256=89af57a45bbf13de4dc91ed7f20b435388c88428eb7dc30639a02b2f0fc2dad1

depends="
    bzip2
    curl
    libbsd
    json-c
    openssl
    zlib
"

makedepends="
    binutils
    bzip2-dev
    cmake
    gcc
    json-c-dev
    libxml2-dev
    make
    ninja
    openssl-dev
    pcre2-dev
    curl-dev
    ncurses-dev
    libunwind-dev
    pkgconf
    rustc
    zlib-dev
    libbsd-dev
"

subpackages="clamav-dev clamav-doc"
recipe_build()
{
	# Proven v0 flags.  CARGO_NET_OFFLINE honours the vendored crates;
	# target-cpu left at baseline for portability across KVM hosts.
	cmake -G Ninja -S "$SRC" -B build \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_SYSCONFDIR=/etc \
		-DCMAKE_INSTALL_LOCALSTATEDIR=/var \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DAPP_CONFIG_DIRECTORY=/etc/clamav \
		-DDATABASE_DIRECTORY=/var/lib/clamav \
		-DCVD_CERTS_DIRECTORY=/etc/clamav/certs \
		-DCLAMAV_USER=clamav -DCLAMAV_GROUP=clamav \
		-DBYTECODE_RUNTIME=interpreter \
		-DENABLE_TESTS=OFF -DENABLE_MILTER=OFF -DENABLE_CLAMONACC=OFF \
		-DENABLE_UNRAR=OFF -DENABLE_SYSTEMD=OFF -DENABLE_DOXYGEN=OFF \
		-DENABLE_EXAMPLES=OFF -DENABLE_STATIC_LIB=OFF \
		-DENABLE_SHARED_LIB=ON -DENABLE_JSON_SHARED=ON \
		-DDO_NOT_SET_RPATH=ON
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	# Split-package carve-outs: clamd -> clamav-daemon, freshclam ->
	# clamav-freshclam.  Sample configs stay with those consumers.
	rm -f "$PKGDEST/usr/sbin/clamd" \
		"$PKGDEST/usr/bin/freshclam" \
		"$PKGDEST/usr/bin/clamdscan" \
		"$PKGDEST/usr/share/man/man8/clamd.8" \
		"$PKGDEST/usr/share/man/man1/freshclam.1" \
		"$PKGDEST/usr/share/man/man1/clamdscan.1" \
		"$PKGDEST/etc/clamav/clamd.conf.sample" \
		"$PKGDEST/etc/clamav/freshclam.conf.sample"
	rm -rf "$PKGDEST/usr/lib/systemd"
	install -d -m 0755 "$PKGDEST/var/lib/clamav"
}

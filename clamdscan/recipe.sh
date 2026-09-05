#!/bin/sh

pkgname=clamdscan
pkgver=1.5.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ClamAV on-demand scanner client for clamd"
license="GPL-2.0-or-later"
origin=clamdscan
repo=main
url=https://www.clamav.net/
source=https://www.clamav.net/downloads/production/clamav-1.5.3.tar.gz
sha256=89af57a45bbf13de4dc91ed7f20b435388c88428eb7dc30639a02b2f0fc2dad1

depends="clamav>=1.5.3-r2"

makedepends="
    binutils
    bzip2-dev
    clamav-dev
    cmake
    gcc
    json-c
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

# Same proven v0 cmake flags as clamav; only the clamdscan target is built.
# CARGO_NET_OFFLINE honours the vendored crates; target-cpu left at
# baseline for portability across KVM hosts.
recipe_build()
{
	cmake -G Ninja "$SRC" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_SYSCONFDIR=/etc \
		-DCMAKE_INSTALL_LOCALSTATEDIR=/var \
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
	CARGO_NET_OFFLINE=true RUSTFLAGS="-Clink-arg=-no-pie" ninja -C "$BUILDDIR" clamdscan
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/clamdscan/clamdscan" \
		"$PKGDEST/usr/bin/clamdscan"
	install -D -m 0644 "$BUILDDIR/docs/man/clamdscan.1" \
		"$PKGDEST/usr/share/man/man1/clamdscan.1"
}

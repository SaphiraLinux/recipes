#!/bin/sh

pkgname=clamav-daemon
pkgver=1.5.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ClamAV scanner daemon (clamd)"
license="GPL-2.0-or-later"
origin=clamav-daemon
repo=main
url=https://www.clamav.net/
source=https://www.clamav.net/downloads/production/clamav-1.5.3.tar.gz
sha256=89af57a45bbf13de4dc91ed7f20b435388c88428eb7dc30639a02b2f0fc2dad1

depends="
    clamav
    curl
    libbsd
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

subpackages="
    $pkgname-doc
"

recipe_build()
{
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
	ninja -C build clamd
}

recipe_install()
{
	install -D -m 0755 build/clamd/clamd \
		"$PKGDEST/usr/sbin/clamd"
	install -D -m 0644 build/docs/man/clamd.8 \
		"$PKGDEST/usr/share/man/man8/clamd.8"
	install -d -m 0755 "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system" "$PKGDEST/etc/clamav" \
		"$PKGDEST/var/log/clamav"
	# Seed config: TCP listener on localhost only, matching mailDragon's
	# rspamd external-services pattern.
	cat > "$PKGDEST/etc/clamav/clamd.conf" <<'EOF'
LogFile /var/log/clamav/clamd.log
LogTime yes
DatabaseDirectory /var/lib/clamav
LocalSocket /run/clamav/clamd.sock
TCPAddr 127.0.0.1
TCPSocket 3310
User clamav
DetectPUA yes
ExcludePUA PUA.Win.Packed
MaxScanSize 100M
MaxFileSize 50M
EOF
	install -m 0644 "$RECIPE_DIR/files/clamd.service" \
		"$PKGDEST/usr/lib/systemd/system/clamd.service"
	install -m 0755 "$RECIPE_DIR/files/clamd.initd" \
		"$PKGDEST/etc/init.d/clamd"
}

#!/bin/sh

pkgname=nmap
pkgver=7.99
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Network security scanner and port analyzer"
license="NPSL-0.95"
origin=nmap
repo=saphira
url=https://nmap.org/
source=https://nmap.org/dist/nmap-7.99.tar.bz2
sha256=df512492ffd108e53a27a06f26d8635bbe89e0e569455dc8ffef058c035d51b2

makedepends="
    binutils
    gcc
    libpcap-dev
    make
    openssl-dev
    pcre2-dev
"

# --without-zenmap: Python GUI deliberately excluded.
# NSE uses the bundled Lua (--with-liblua=included; system lua54 is not
# wired into nmap's configure). --without-libssh2: no libssh2 recipe yet.
recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --without-zenmap --with-openssl=/usr \
		--with-libpcap=/usr --with-libpcre=/usr --with-liblua=included \
		--without-libssh2
	make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

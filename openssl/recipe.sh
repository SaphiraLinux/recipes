#!/bin/sh
pkgname=openssl
pkgver=3.6.3
pkgrel=4
# r3: /etc/ssl/private ships 0700 (homer recon carries 0700;
# upstream install_ssldirs leaves 0755 on the private-key
# directory). Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='TLS/SSL and crypto library (Genesis base)'
license='Apache-2.0'
origin=openssl
repo=saphira
url=https://www.openssl.org/
# Upstream tarball. vendor=+sha256= is the fetch contract: when the archive
# is absent from files/, the builder downloads vendor=, verifies sha256,
# and exposes the verified archive as $SOURCE_ARCHIVE. A present local
# archive always wins and is never re-downloaded.
vendor=https://www.openssl.org/source/openssl-3.6.3.tar.gz
sha256=243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1
depends=""
makedepends="
	binutils
	gcc
	make
	perl
	zlib-dev
"
subpackages="$pkgname-dev"
recipe_build() {
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE.
	OSSLBALL="$RECIPE_DIR/files/openssl-3.6.3.tar.gz"
	if [ -f "$OSSLBALL" ]; then
		echo "$sha256  $OSSLBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local openssl-3.6.3.tar.gz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		OSSLBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$OSSLBALL"
	cd "$SRC"
	# OpenSSL Configure takes an explicit target and does not reliably
	# infer it here: a hardcoded linux-x86_64 emits x86-only -m64 on
	# aarch64 and the build dies immediately. Select by package arch and
	# fail closed otherwise (a silent default is how a mislabelled
	# package reaches a signed repository). x86_64 resolves to the
	# previous literal, so the x86_64 payload is unchanged.
	case "$pkgarch" in
		x86_64) OSSL_TARGET=linux-x86_64 ;;
		aarch64) OSSL_TARGET=linux-aarch64 ;;
		riscv64) OSSL_TARGET=linux-riscv64 ;;
		*) echo "ERROR: no OpenSSL target for $pkgarch" >&2; return 1 ;;
	esac
	./Configure "$OSSL_TARGET" \
		--prefix=/usr --libdir=lib --openssldir=/etc/ssl \
		shared no-tests zlib
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install_sw install_ssldirs
	find "$PKGDEST" -name '*.la' -delete
	# Private-key directory: root-only listing.
	install -d -m 0700 "$PKGDEST/etc/ssl/private"
}

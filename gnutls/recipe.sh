pkgname=gnutls
pkgver=3.8.12
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU TLS library (libvirt mandatory TLS dependency)'
license='LGPL-2.1-or-later'
origin=gnutls
repo=main
url=https://www.gnutls.org/
source=https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.12.tar.xz
sha256=a7b341421bfd459acf7a374ca4af3b9e06608dcd7bd792b2bf470bea012b8e51

depends="nettle libtasn1 libunistring zlib"
makedepends="
	binutils
	gawk
	gcc
	libunistring-dev
	libtasn1
	libtasn1-dev
	make
	nettle-dev
	pkgconf
	zlib-dev
"

# v0-proven flags: no p11-kit/idn/zstd/brotli/tpm on Saphira; musl-native.
# Release tarball ships configure.
subpackages="$pkgname-dev"

recipe_build()
{
	./configure --prefix=/usr --disable-static --disable-doc --disable-tests \
		--without-p11-kit --without-idn --without-zstd --without-brotli \
		--without-tpm2 --without-tpm \
		--disable-dependency-tracking
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# libtool .la files poison dependent builds with dangling
	# requires (e.g. libunistring.la); drop them.
	find "$PKGDEST" -name '*.la' -delete
}

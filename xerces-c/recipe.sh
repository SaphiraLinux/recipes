#!/bin/sh
pkgname=xerces-c
pkgver=3.3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Validating C++ XML parser (Xerces-C++, Intel LMS dependency)'
license='Apache-2.0'
origin=xerces-c
repo=saphira
url=https://xerces.apache.org/xerces-c/
source=https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-3.3.0.tar.gz
sha256=9555f1d06f82987fbb4658862705515740414fd34b4db6ad2ed76a2dc08d3bde

# Headless, minimal closure, fully explicit (never autodetect):
# transcoder=iconv (musl iconv is native; ICU exists in tree but an
# XML parser must not drag 80MB of Unicode tables for LMS config
# files), network-accessor=socket (not curl), message-loader=inmemory
# (not icu). Nothing about XML parsing needs X11, SaaS, or network
# clients; those stacks stay out of the closure by construction.
# The C++ library and sample tools need the compiler runtime
# (gcc-libs convention, never the full compiler).
depends="gcc-libs"
makedepends="binutils cmake gcc make pkgconf"
subpackages="$pkgname-dev"

recipe_build() {
	XERCES_BALL="$RECIPE_DIR/files/xerces-c-${pkgver}.tar.gz"
	echo "$sha256  $XERCES_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$XERCES_BALL"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-Dtranscoder=iconv \
		-Dnetwork-accessor=socket \
		-Dmessage-loader=inmemory
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.a' -delete
}

#!/bin/sh

pkgname=jbig2dec
pkgver=0.20
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="JBIG2 image decoder library (Ghostscript dependency)"
license='AGPL-3.0-or-later'
origin=jbig2dec
repo=saphira
url=https://github.com/ArtifexSoftware/jbig2dec
source=https://github.com/ArtifexSoftware/jbig2dec/releases/download/0.20/jbig2dec-0.20.tar.gz
sha256=7b63ff6470289547e7a3a0f145cb8ea6c2afffdd65645b7d87d3b7febc96fb3a

# NOTE: AGPL-3.0, like Ghostscript which consumes it. Saphira states
# the upstream licence as-is; this recipe only builds it. Consumers
# link it as a shared library (no static bundling).
depends=""

makedepends="
    gcc
    make
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/jbig2dec-0.20.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/jbig2dec-0.20.tar.gz" | sha256sum -c -
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --libdir=/usr/lib
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# AGPL licence text ships with the package (redistribution
	# obligations attach to this NVR; the text must travel with it).
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/jbig2dec/COPYING"
}

#!/bin/sh

pkgname=giflib
pkgver=5.2.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GIF image format library (headless image codec, OpenJDK imageio chain)'
license='MIT'
origin=giflib
repo=saphira
url=http://giflib.sourceforge.net/
source=https://sourceforge.net/projects/giflib/files/giflib-5.2.2.tar.gz/download
sha256=be7ffbd057cadebe2aa144542fd90c6838c6a083b5e8a9048b8ee3b66b29d5fb

depends="
"

makedepends="
    binutils
    gcc
    make
"

subpackages="$pkgname-dev"

# Plain C codec, no GUI, no optional dependencies. The getarg
# utility needs getopt (libc) only. Vendored tarball verified
# against the Chimera cports pin before vendoring.
# The worker keys vendored archives by URL basename ("download" here),
# so it cannot match files/giflib-5.2.2.tar.xz; it would re-download
# instead. Read the vendored, sidecar-verified archive directly and
# fail closed when absent — the same converted-recipe idiom as
# openjdk17-bootstrap. The download URL still works and is kept for
# provenance.
# Upstream ships hand-written Makefiles, no configure. PREFIX/DESTDIR
# are honored by the install targets (verified against the Makefile).
# The doc sub-make needs ImageMagick's `convert` for a logo; docs are
# not built (man sources ship prebuilt and install without it).
# Explicit lib+tool targets instead of `all`, then the install
# sub-targets directly (the `install` wrapper would rebuild docs).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/giflib-5.2.2.tar.gz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/giflib-5.2.2.tar.gz" \
		-C "$BUILDDIR" --strip-components=1
	make -C "$BUILDDIR" PREFIX=/usr libgif.so libgif.a \
		libutil.so libutil.a gif2rgb gifbuild giffix giftext \
		giftool gifclrmp gifbg gifcolor gifecho giffilter \
		gifhisto gifinto gifsponge gifwedge
}

recipe_install()
{
	make -C "$BUILDDIR" PREFIX=/usr DESTDIR="$PKGDEST" \
		install-bin install-include install-lib install-man
}

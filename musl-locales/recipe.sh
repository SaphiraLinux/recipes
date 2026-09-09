#!/bin/sh

# musl locale data (LC_TIME/LC_COLLATE/LC_NUMERIC beyond built-in C).
# Upstream is untagged since 2019-02-28, so the version is a date
# snapshot of the pinned commit, not a release. There is deliberately
# no localedef, no /etc/locale.gen, no locale-archive: on musl the
# package IS the generated output, consumed via MUSL_LOCPATH (the
# profile default lands separately with baselayout). tzdata-shaped
# data recipe: install, no compilation beyond the data build itself.

pkgname=musl-locales
pkgver=20190228
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Locale data for musl (MUSL_LOCPATH)"
license="MIT"
origin=musl-locales
repo=saphira
url=https://github.com/rilian-la-te/musl-locales
source=https://github.com/rilian-la-te/musl-locales/archive/76fcf3c822b77a987657f0832c873c465b842438.tar.gz
sha256=cb938e14cba69009a75e9307f31a8dae2dcbdaccc7506378188e9b9071328bc5

depends=""

makedepends="
    binutils
    cmake
    gcc
    make
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

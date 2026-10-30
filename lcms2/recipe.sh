#!/bin/sh

pkgname=lcms2
pkgver=2.19.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Little CMS 2 color management engine (library and utilities)"
license='MIT'
origin=lcms2
repo=saphira
url=https://littlecms.com/
source=https://github.com/mm2/Little-CMS/releases/download/lcms2.19.1/lcms2-2.19.1.tar.gz
sha256=bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8

depends="zlib"

makedepends="
    gcc
    make
    zlib-dev
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/lcms2-2.19.1.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/lcms2-2.19.1.tar.gz" | sha256sum -c -
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --libdir=/usr/lib
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	test -f "$SRC/LICENSE" || {
		echo "ERROR: upstream licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/lcms2/LICENSE"
	# jpgicc utility ships under the IJG licence, not MIT.
	test -f "$SRC/utils/jpgicc/LICENSE_iccjpeg" || {
		echo "ERROR: jpgicc licence file missing from source tree" >&2
		return 1
	}
	install -D -m 0644 "$SRC/utils/jpgicc/LICENSE_iccjpeg" \
		"$PKGDEST/usr/share/licenses/lcms2/LICENSE.iccjpeg"
}

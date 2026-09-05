#!/bin/sh

pkgname=distlib
pkgver=0.4.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python library implementing low-level components of pip and virtualenv"
license="PSF-2.0"
origin=distlib
repo=saphira
url=https://github.com/pypa/distlib
source=https://pypi.io/packages/source/d/distlib/distlib-0.4.3.tar.gz
sha256=f152097224a0ae24be5a0f6bae1b9359af82133bce63f98a95f86cae1aede9ed

depends="
    python3
"

recipe_build()
{
	:
}

recipe_install()
{
	local site=$PKGDEST/usr/lib/python3.14/site-packages
	install -d -m 0755 "$site"
	cp -a "$SRC/distlib" "$site/"
	install -d -m 0755 "$site/distlib-0.4.3.dist-info"
	printf '%s\n' \
		'Metadata-Version: 2.1' \
		'Name: distlib' \
		'Version: 0.4.3' \
		> "$site/distlib-0.4.3.dist-info/METADATA"
}

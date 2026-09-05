#!/bin/sh

pkgname=python-markupsafe
pkgver=3.0.3
pkgrel=1
pkgarch=noarch
pkgdesc="Safely mark strings for Python HTML/XML generation"
license="BSD-3-Clause"
origin=markupsafe
repo=main
url=https://palletsprojects.com/p/markupsafe/
source=https://files.pythonhosted.org/packages/source/M/MarkupSafe/markupsafe-${pkgver}.tar.gz
sha256=722695808f4b6457b320fdc131280796bdceb04ab50fe1795cd540799ebe1698

depends="
    python3
"

makedepends="
    python3
    python3-pip
"

recipe_build()
{
	:
}

recipe_install()
{
	python3 -m pip install \
		--ignore-installed \
		--no-deps \
		--no-cache-dir \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"
}

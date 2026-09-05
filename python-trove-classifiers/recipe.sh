#!/bin/sh

pkgname=python-trove-classifiers
pkgver=2025.9.11.17
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Canonical PyPI trove classifier names"
license="MIT"
origin=trove-classifiers
repo=saphira
url=https://pypi.org/project/trove-classifiers/
source=https://files.pythonhosted.org/packages/ca/9a/778622bc06632529817c3c524c82749a112603ae2bbcf72ee3eb33a2c4f1/trove_classifiers-2025.9.11.17.tar.gz
sha256=931ca9841a5e9c9408bc2ae67b50d28acf85bef56219b56860876dd1f2d024dd

depends="python3"
makedepends="
    python3
    python3-pip
    setuptools
"

recipe_build() {
	:
}

recipe_install() {
	python3 -m pip install 		--no-deps 		--no-build-isolation 		--no-compile 		--root "$PKGDEST" 		--prefix /usr 		"$SRC"
}

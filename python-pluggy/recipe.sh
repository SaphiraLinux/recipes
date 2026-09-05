#!/bin/sh

pkgname=python-pluggy
pkgver=1.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="pytest plugin hook system"
license="MIT"
origin=pluggy
repo=saphira
url=https://pypi.org/project/pluggy/
source=https://files.pythonhosted.org/packages/f9/e2/3e91f31a7d2b083fe6ef3fa267035b518369d9511ffab804f839851d2779/pluggy-1.6.0.tar.gz
sha256=7dcc130b76258d33b90f61b658791dede3486c3e6bfb003ee5c9bfb396dd22f3

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

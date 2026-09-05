#!/bin/sh

pkgname=python-pathspec
pkgver=1.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PEP 517 backend flit_core; filesystem path utilities"
license="MIT"
origin=pathspec
repo=saphira
url=https://pypi.org/project/pathspec/
source=https://files.pythonhosted.org/packages/5a/82/42f767fc1c1143d6fd36efb827202a2d997a375e160a71eb2888a925aac1/pathspec-1.1.1.tar.gz
sha256=17db5ecd524104a120e173814c90367a96a98d07c45b2e10c2f3919fff91bf5a

depends="python3"
makedepends="
    python3
    python3-pip
    setuptools
    python-flit-core
"

recipe_build() {
	:
}

recipe_install() {
	python3 -m pip install 		--no-deps 		--no-build-isolation 		--no-compile 		--root "$PKGDEST" 		--prefix /usr 		"$SRC"
}

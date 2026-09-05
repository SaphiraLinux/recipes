#!/bin/sh

pkgname=python-setuptools-scm
pkgver=9.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Manage versions by git tags (setuptools plugin and python package)"
license="MIT"
origin=setuptools_scm
repo=saphira
url=https://pypi.org/project/setuptools-scm/
source=https://files.pythonhosted.org/packages/6d/5a/bac96e8fa2629bebb89709fce29330326ecf32146f4bf96d0ee31e182e0e/setuptools_scm-9.1.0.tar.gz
sha256=24a91d815e81905b6029191dcf6e7fa54760066d8371252e8a90e7bee4e8fcb6

depends="
    python3
    packaging
    setuptools
"
makedepends="python3 python3-pip setuptools"

recipe_build() {
	:
}

recipe_install() {
	python3 -m pip install \
		--no-deps \
		--no-build-isolation \
		--no-compile \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"
}

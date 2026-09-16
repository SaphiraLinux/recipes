#!/bin/sh

# Hatch plugin: Hatch plugin for fancy PyPI readmes (attrs build tooling)
#
# PyPI hatch-fancy-pypi-readme 25.1.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# hatchling backend, static version; exists so attrs can build offline.

pkgname=python-hatch-fancy-pypi-readme
pkgver=25.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Hatch plugin for fancy PyPI readmes (attrs build tooling)"
license="MIT"
origin=hatch-fancy-pypi-readme
repo=saphira
url=https://pypi.org/project/hatch-fancy-pypi-readme/
source=https://files.pythonhosted.org/packages/f3/0f/aed57c301f339936eb91cb4d8c1e5088a101081854bd3ec18a889df32365/hatch_fancy_pypi_readme-25.1.0.tar.gz
sha256=9c58ed3dff90d51f43414ce37009ad1d5b0f08ffc9fc216998a06380f01c0045

depends="
    python3
    python-hatchling
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-hatchling
"

recipe_build()
{
    :
}

recipe_install()
{
    python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}

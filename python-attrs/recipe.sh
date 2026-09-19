#!/bin/sh

# Classes Without Boilerplate: Classes Without Boilerplate
#
# PyPI attrs 26.1.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# hatchling+hatch-vcs backend; version pre-seeded like tabulate (no .git in tree). hatch-fancy-pypi-readme renders the readme fragments at build time.

pkgname=python-attrs
pkgver=26.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Classes Without Boilerplate"
license="MIT"
origin=attrs
repo=saphira
url=https://pypi.org/project/attrs/
source=https://files.pythonhosted.org/packages/9a/8e/82a0fe20a541c03148528be8cac2408564a6c9a0cc7e9171802bc1d26985/attrs-26.1.0.tar.gz
sha256=d03ceb89cb322a8fd706d4fb91940737b6642aa36998fe130a9bc96c985eff32

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-hatchling
    python-hatch-vcs
    python-hatch-fancy-pypi-readme
"

recipe_build()
{
    :
}

recipe_install()
{
    export SETUPTOOLS_SCM_PRETEND_VERSION=26.1.0
    python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}

#!/bin/sh

# expandvars: expand Unix-style system variables.
#
# PyPI expandvars 1.1.2, vendored sdist, pip-installed offline.
# hatchling backend with a static in-source version (no VCS
# tricks). Exists as build tooling: the aio-libs in-tree PEP 517
# backends (frozenlist, yarl, propcache) import it at build time.

pkgname=python-expandvars
pkgver=1.1.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Expand Unix-style system variables in Python"
license="MIT"
origin=expandvars
repo=saphira
url=https://pypi.org/project/expandvars/
source=https://files.pythonhosted.org/packages/9c/64/a9d8ea289d663a44b346203a24bf798507463db1e76679eaa72ee6de1c7a/expandvars-1.1.2.tar.gz
sha256=6c5822b7b756a99a356b915dd1267f52ab8a4efaa135963bd7f4bd5d368f71d7

depends="
    python3
"
makedepends="
    python3
    python3-pip
    python-hatchling
    setuptools
    wheel
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

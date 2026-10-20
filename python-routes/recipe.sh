#!/bin/sh

# python-routes: routes 2.5.1
#
# PyPI routes 2.5.1, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-routes
pkgver=2.5.1
pkgrel=1
pkgarch=noarch
pkgdesc="routes Python library"
license="MIT"
origin=routes
repo=saphira
url=https://pypi.org/project/routes/
source=https://files.pythonhosted.org/packages/62/01/1504b710f68840f4152d460a4ffbc6b8265485b636235ddd72a8dfe686ae/Routes-2.5.1.tar.gz
sha256=b6346459a15f0cbab01a45a90c3d25caf980d4733d628b4cc1952b865125d053

depends="
    python3
    python-six
    python-repoze-lru
"
makedepends="
    python3
    python3-pip
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
        --no-index \
        --no-deps \
        --ignore-installed \
        --no-build-isolation \
        --no-compile \
        --no-cache-dir \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
}

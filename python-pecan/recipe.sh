#!/bin/sh

# python-pecan: A WSGI object-dispatching web framework, designed to be lean and fast, with few dependencies.
#
# pecan 1.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pecan
pkgver=1.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="A WSGI object-dispatching web framework, designed to be lean and fast, with few dependencies. (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=pecan
repo=saphira
url=https://pypi.org/project/pecan/
source=https://files.pythonhosted.org/packages/65/7a/1a69bbc37a5150d17d2955322797f0b3f1f2ca9757e53761c339caa8a4df/pecan-1.8.0.tar.gz
sha256=2f9fbcea86e8dbf1a2d28954225547634a289db7201e7764516a5dce86c116de

depends="
    python3
    python-mako
    python-webob
    setuptools"

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

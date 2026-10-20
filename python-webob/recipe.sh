#!/bin/sh

# python-webob: WebOb 1.8.11
#
# PyPI WebOb 1.8.11, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-webob
pkgver=1.8.11
pkgrel=1
pkgarch=noarch
pkgdesc="WebOb Python library"
license="MIT"
origin=WebOb
repo=saphira
url=https://pypi.org/project/WebOb/
source=https://files.pythonhosted.org/packages/e6/92/9329872e36be90e25ba616ac6e9ee8c1be4326a1ea3fdffcdabd0eb48efb/webob-1.8.11.tar.gz
sha256=aa8c27231070b135c025e567a9cd7eda03f4df71352ffaac740cb6a75f0f81a5

depends="
    python3
    python-legacy-cgi
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

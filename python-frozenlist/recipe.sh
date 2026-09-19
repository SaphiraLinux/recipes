#!/bin/sh

# List-like structure with frozen support: List-like structure with frozen support for aiohttp
#
# PyPI frozenlist 1.8.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# In-tree pep517 backend; C extension compiled with gcc (pure fallback exists but the build takes the fast path).

pkgname=python-frozenlist
pkgver=1.8.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="List-like structure with frozen support for aiohttp"
license="Apache-2.0"
origin=frozenlist
repo=saphira
url=https://pypi.org/project/frozenlist/
source=https://files.pythonhosted.org/packages/2d/f5/c831fac6cc817d26fd54c7eaccd04ef7e0288806943f7cc5bbf69f3ac1f0/frozenlist-1.8.0.tar.gz
sha256=3ede829ed8d842f6cd48fc7081d7a41001a56f1f38603f9d49bf3020d59a31ad

depends="
    python3
"
makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python3-dev
    python-expandvars
    cython
    gcc
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

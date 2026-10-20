#!/bin/sh

# python-memcached: python-memcached 1.62
#
# PyPI python-memcached 1.62, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-memcached
pkgver=1.62
pkgrel=1
pkgarch=noarch
pkgdesc="python-memcached Python library"
license="PSF-2.0"
origin=python-memcached
repo=saphira
url=https://pypi.org/project/python-memcached/
source=https://files.pythonhosted.org/packages/e8/3c/204e5c6087efc85b52a68edce8678d44eb28718f5f145e036c277beb467c/python-memcached-1.62.tar.gz
sha256=0285470599b7f593fbf3bec084daa1f483221e68c1db2cf1d846a9f7c2655103

depends="
    python3
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

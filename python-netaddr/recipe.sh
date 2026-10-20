#!/bin/sh

# python-netaddr: netaddr 1.3.0
#
# PyPI netaddr 1.3.0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.

pkgname=python-netaddr
pkgver=1.3.0
pkgrel=1
pkgarch=noarch
pkgdesc="netaddr Python library"
license="BSD-3-Clause"
origin=netaddr
repo=saphira
url=https://pypi.org/project/netaddr/
source=https://files.pythonhosted.org/packages/54/90/188b2a69654f27b221fba92fda7217778208532c962509e959a9cee5229d/netaddr-1.3.0.tar.gz
sha256=5c3c3d9895b551b763779ba7db7a03487dc1f8e3b385af819af341ae9ef6e48a

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

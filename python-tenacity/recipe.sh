#!/bin/sh

# python-tenacity: Retry code until it succeeds
#
# tenacity 9.1.4, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-tenacity
pkgver=9.1.4
pkgrel=1
pkgarch=noarch
pkgdesc="Retry code until it succeeds (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=tenacity
repo=saphira
url=https://pypi.org/project/tenacity/
source=https://files.pythonhosted.org/packages/47/c6/ee486fd809e357697ee8a44d3d69222b344920433d3b6666ccd9b374630c/tenacity-9.1.4.tar.gz
sha256=adb31d4c263f2bd041081ab33b498309a57c77f9acf2db65aadf0898179cf93a

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

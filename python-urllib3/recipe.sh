#!/bin/sh

pkgname=python-urllib3
pkgver=2.7.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python HTTP library with thread-safe connection pooling"
license="MIT"
origin=urllib3
repo=saphira
url=https://pypi.org/project/urllib3/
source=https://files.pythonhosted.org/packages/53/0c/06f8b233b8fd13b9e5ee11424ef85419ba0d8ba0b3138bf360be2ff56953/urllib3-2.7.0.tar.gz
sha256=231e0ec3b63ceb14667c67be60f2f2c40a518cb38b03af60abc813da26505f4c

depends="
    python3
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-hatch-vcs
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

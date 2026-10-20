#!/bin/sh

# python-platformdirs: small Python package for determining appropriate
# platform-specific directories (user data dir, config dir, ...).
#
# platformdirs 4.11.3, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-platformdirs
pkgver=4.11.3
pkgrel=1
pkgarch=noarch
pkgdesc="A small Python package for determining appropriate platform-specific dirs (OpenStack 2026.2 closure)"
license='MIT'
origin=platformdirs
repo=saphira
url=https://pypi.org/project/platformdirs/
source=https://files.pythonhosted.org/packages/b8/d7/e7bfbc86e9f99ff7807e24de7703f032e9c9ba80bb355cf26e0e9bc5a75e/platformdirs-4.11.3.tar.gz
sha256=66a73d38a849810252df809a3d8bcbda8e26f6c189920e7535ad608a48dbb5ab

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-hatchling
    python-hatch-vcs
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

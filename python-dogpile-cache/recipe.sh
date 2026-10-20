#!/bin/sh

# python-dogpile-cache: dogpile.cache: caching API with a dogpile lock (oslo.cache backend)
#
# dogpile.cache 1.5.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-dogpile-cache
pkgver=1.5.0
pkgrel=1
pkgarch=noarch
pkgdesc="dogpile.cache: caching API with a dogpile lock (oslo.cache backend)"
license="MIT"
origin=dogpile.cache
repo=saphira
url=https://pypi.org/project/dogpile.cache/
source=https://files.pythonhosted.org/packages/e7/c8/301ff89746e76745b937606df4753c032787c59ecb37dd4d4250bddc8929/dogpile_cache-1.5.0.tar.gz
sha256=849c5573c9a38f155cd4173103c702b637ede0361c12e864876877d0cd125eec

depends="
    python3
    python-decorator
    python-stevedore
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

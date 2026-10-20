#!/bin/sh

# python-importlib-metadata: Read metadata from Python packages
#
# importlib_metadata 9.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-importlib-metadata
pkgver=9.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="Read metadata from Python packages (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=importlib_metadata
repo=saphira
url=https://pypi.org/project/importlib_metadata/
source=https://files.pythonhosted.org/packages/a9/01/15bb152d77b21318514a96f43af312635eb2500c96b55398d020c93d86ea/importlib_metadata-9.0.0.tar.gz
sha256=a4f57ab599e6a2e3016d7595cfd72eb4661a5106e787a95bcc90c7105b831efc

depends="
    python3
    python-zipp"

makedepends="
    python3
    python3-pip
    python-pbr
    setuptools
    wheel
    python-setuptools-scm
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

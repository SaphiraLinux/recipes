#!/bin/sh

# python-zipp: Backport of pathlib-compatible object wrapper for zip files
#
# zipp 4.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-zipp
pkgver=4.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="Backport of pathlib-compatible object wrapper for zip files (OpenStack 2026.2 closure)"
license='MIT'
origin=zipp
repo=saphira
url=https://pypi.org/project/zipp/
source=https://files.pythonhosted.org/packages/b9/d8/eab98a517c14134c0b2eb4e2387bc5f457334293ec5d2dd3857ec2966802/zipp-4.1.0.tar.gz
sha256=4cb57381f544315db7688e976e922a2b18cdb513d21cc194eb42232ba2a3e602

depends="
    python3
"

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

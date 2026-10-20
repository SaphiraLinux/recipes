#!/bin/sh

# python-os-service-types: os-service-types: OpenStack service type database (keystoneauth1)
#
# os-service-types 1.9.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-os-service-types
pkgver=1.9.0
pkgrel=1
pkgarch=noarch
pkgdesc="os-service-types: OpenStack service type database (keystoneauth1)"
license="Apache-2.0"
origin=os-service-types
repo=saphira
url=https://pypi.org/project/os-service-types/
source=https://files.pythonhosted.org/packages/86/ae/fe7ac23155ae0b4b9779e06e9c5bb4070f2315dc4ca886a88fa3230d344b/os_service_types-1.9.0.tar.gz
sha256=1f2e5fb71d1f6f4ff31d8992674f2368465bc2f25cd94018015c3ddbfc5c617f

depends="
    python3
    python-pbr
    typing-extensions
"
makedepends="
    python3
    python3-pip
    python-pbr
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

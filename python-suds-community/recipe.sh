#!/bin/sh

# python-suds-community: Lightweight SOAP client (community fork)
#
# suds-community 1.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-suds-community
pkgver=1.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="Lightweight SOAP client (community fork) (OpenStack 2026.2 closure)"
license='LGPL-3.0-only'
origin=suds-community
repo=saphira
url=https://pypi.org/project/suds-community/
source=https://files.pythonhosted.org/packages/9e/5d/da767935b4cb869417307fbd6dec93d2bf3723228214302b6e6b277f474b/suds_community-1.2.0.tar.gz
sha256=ab3b24dc9ba06b5e6598e2a5d34d2a7d06c79e613d81cedc028475bfbd3bb90c

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

#!/bin/sh

# python-oslo-i18n: oslo.i18n: OpenStack i18n translation utilities
#
# oslo.i18n 6.9.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-i18n
pkgver=6.9.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.i18n: OpenStack i18n translation utilities"
license="Apache-2.0"
origin=oslo.i18n
repo=saphira
url=https://pypi.org/project/oslo.i18n/
source=https://files.pythonhosted.org/packages/5e/69/72b03bb4d33f51a157c02d5297227bae48b9c359103856942b8774b608df/oslo_i18n-6.9.0.tar.gz
sha256=574bcf21873b185068bcec951de1ec093158ffdff05a8055fd18ddcb69f69e65

depends="
    python3
    python-pbr
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

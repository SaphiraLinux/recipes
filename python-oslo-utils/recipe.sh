#!/bin/sh

# python-oslo-utils: oslo.utils: OpenStack common utility library
#
# oslo.utils 10.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-utils
pkgver=10.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.utils: OpenStack common utility library"
license="Apache-2.0"
origin=oslo.utils
repo=saphira
url=https://pypi.org/project/oslo.utils/
source=https://files.pythonhosted.org/packages/47/fd/7915fc0e2c959bcb3dbbe608deeeefe4264d03ba89a4fd75d74524326652/oslo_utils-10.2.0.tar.gz
sha256=ba839dea2c1eb415e3ee151c4cc688f52e283f59bc1f77cc86772190a8b34259

depends="
    python3
    python-iso8601
    python-oslo-i18n
    python-netaddr
    pyparsing
    packaging
    pyyaml
    python-psutil
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

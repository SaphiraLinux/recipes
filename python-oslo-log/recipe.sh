#!/bin/sh

# python-oslo-log: oslo.log: OpenStack logging configuration library
#
# oslo.log 8.3.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-log
pkgver=8.3.2
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.log: OpenStack logging configuration library"
license="Apache-2.0"
origin=oslo.log
repo=saphira
url=https://pypi.org/project/oslo.log/
source=https://files.pythonhosted.org/packages/11/ae/aad4d9ae5afdca9d09d41b498fced798dbda03f0e64281f9d410f72a639e/oslo_log-8.3.2.tar.gz
sha256=478a5cbae4375c42f2e114ea0aafda105b8753b9b8bd1acc09d154a254048002

depends="
    python3
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-utils
    python-oslo-serialization
    python-dateutil
    python-debtcollector
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

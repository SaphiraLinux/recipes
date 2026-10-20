#!/bin/sh

# python-oslo-vmware: Oslo VMware library
#
# oslo.vmware 4.10.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-vmware
pkgver=4.10.1
pkgrel=1
pkgarch=noarch
pkgdesc="Oslo VMware library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=oslo.vmware
repo=saphira
url=https://pypi.org/project/oslo.vmware/
source=https://files.pythonhosted.org/packages/a9/69/680bfbe4a500eec1c1cfa4c126137a26ba07f1b0dac730efc4df9958fb20/oslo_vmware-4.10.1.tar.gz
sha256=4864aa6a4cd8568ff6120927117b07d9203764e996e4dab775acd98ac40f11a5

depends="
    python3
    python-lxml
    python-oslo-concurrency
    python-oslo-context
    python-oslo-i18n
    python-oslo-service
    python-oslo-utils
    python-pbr
    python-requests
    python-suds-community
    python-urllib3"

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

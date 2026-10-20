#!/bin/sh

# python-oslo-config: oslo.config: OpenStack configuration API (oslo-config-generator)
#
# oslo.config 10.7.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-config
pkgver=10.7.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.config: OpenStack configuration API (oslo-config-generator)"
license="Apache-2.0"
origin=oslo.config
repo=saphira
url=https://pypi.org/project/oslo.config/
source=https://files.pythonhosted.org/packages/74/cd/e9e312ca216eaa9e0fa76f8d8fb9aeb14ea56f136136ec6753a11df24237/oslo_config-10.7.0.tar.gz
sha256=4f0fd4ca7ecfe511fbc0e012d3c63fce57009f360199e9e9cc2329ed55ec911e

depends="
    python3
    python-netaddr
    python-stevedore
    python-oslo-i18n
    python-rfc3986
    pyyaml
    python-requests
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

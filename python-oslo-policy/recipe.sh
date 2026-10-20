#!/bin/sh

# python-oslo-policy: oslo.policy: OpenStack policy enforcement (oslo-policy-generator)
#
# oslo.policy 6.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-policy
pkgver=6.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.policy: OpenStack policy enforcement (oslo-policy-generator)"
license="Apache-2.0"
origin=oslo.policy
repo=saphira
url=https://pypi.org/project/oslo.policy/
source=https://files.pythonhosted.org/packages/c8/1e/71f9edfe473164f185adc3f9c9795678fb74dbf4dd0036468ef3b9b3d2e1/oslo_policy-6.0.1.tar.gz
sha256=0983259d3919b15caa3755b22fba1451904f60ac20a48656bc61afaf420f7a67

depends="
    python3
    python-requests
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-serialization
    pyyaml
    python-stevedore
    python-oslo-utils
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

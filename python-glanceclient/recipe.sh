#!/bin/sh

# python-glanceclient: OpenStack Image API Client Library
#
# python-glanceclient 4.13.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-glanceclient
pkgver=4.13.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack Image API Client Library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=python-glanceclient
repo=saphira
url=https://pypi.org/project/python-glanceclient/
source=https://files.pythonhosted.org/packages/66/ea/d65c3c097d1ab72aca5fde2149fd35f70d08521473711acb82a3f8af0abf/python_glanceclient-4.13.0.tar.gz
sha256=fa3359bc8bd93e7aebca372dafec8e19003b4c1f64499e2eb82b2771da8fa41c

depends="
    python3
    python-keystoneauth1
    python-oslo-i18n
    python-oslo-utils
    python-pbr
    python-prettytable
    python-openssl
    python-requests
    python-warlock
    python-wrapt"

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

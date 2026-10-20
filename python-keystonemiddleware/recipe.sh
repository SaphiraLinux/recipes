#!/bin/sh

# python-keystonemiddleware: keystonemiddleware: Keystone auth middleware for OpenStack WSGI services
#
# keystonemiddleware 13.0.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-keystonemiddleware
pkgver=13.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="keystonemiddleware: Keystone auth middleware for OpenStack WSGI services"
license="Apache-2.0"
origin=keystonemiddleware
repo=saphira
url=https://pypi.org/project/keystonemiddleware/
source=https://files.pythonhosted.org/packages/03/21/b589d73848e41a8880f1788dae6f6934c7440cb40ab7d56cee21988ed51a/keystonemiddleware-13.0.1.tar.gz
sha256=0f599645711fb7beb2721bfa409d92b69b5c3ee3788fd5d1f5db0e57f38f44a7

depends="
    python3
    python-keystoneauth1
    python-oslo-cache
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-log
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-pycadf
    python-pyjwt
    python-keystoneclient
    python-requests
    python-webob
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

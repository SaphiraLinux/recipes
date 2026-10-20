#!/bin/sh

# python-oslo-service: oslo.service: OpenStack service framework (WSGI, periodic tasks)
#
# oslo.service 4.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-service
pkgver=4.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.service: OpenStack service framework (WSGI, periodic tasks)"
license="Apache-2.0"
origin=oslo.service
repo=saphira
url=https://pypi.org/project/oslo.service/
source=https://files.pythonhosted.org/packages/a6/9b/ad4836f44713a6bf3f36f4f1965ac1ab756a124dfb40844d5a4b94342bcc/oslo_service-4.8.0.tar.gz
sha256=5f82357f4c8b20bf40b530262c87b829da4ab1631dfe6e5801ecf6e5d86c60a9

depends="
    python3
    python-webob
    python-debtcollector
    python-eventlet
    python-greenlet
    python-oslo-utils
    python-oslo-concurrency
    python-oslo-config
    python-oslo-log
    python-oslo-i18n
    python-pastedeploy
    python-routes
    python-paste
    python-yappi
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

#!/bin/sh

# python-oslo-messaging: oslo.messaging: OpenStack RPC and notifications
#
# oslo.messaging 18.3.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-messaging
pkgver=18.3.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.messaging: OpenStack RPC and notifications"
license="Apache-2.0"
origin=oslo.messaging
repo=saphira
url=https://pypi.org/project/oslo.messaging/
source=https://files.pythonhosted.org/packages/c3/33/eda37a341dad350cc0790180ddce4666287974a842bef07defc9b19d9074/oslo_messaging-18.3.0.tar.gz
sha256=a468bee8226e3e79878cab1904a8959fd4f924f3a6474470343f51b0818cb745

depends="
    python3
    python-futurist
    python-oslo-config
    python-oslo-context
    python-oslo-log
    python-oslo-utils
    python-oslo-serialization
    python-oslo-service
    python-stevedore
    python-debtcollector
    python-cachetools
    python-webob
    pyyaml
    python-amqp
    python-kombu
    python-oslo-middleware
    python-oslo-metrics
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

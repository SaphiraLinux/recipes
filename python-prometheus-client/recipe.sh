#!/bin/sh

# python-prometheus-client: prometheus-client: Prometheus metrics client (oslo.metrics)
#
# prometheus-client 0.26.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-prometheus-client
pkgver=0.26.0
pkgrel=1
pkgarch=noarch
pkgdesc="prometheus-client: Prometheus metrics client (oslo.metrics)"
license="Apache-2.0"
origin=prometheus-client
repo=saphira
url=https://pypi.org/project/prometheus-client/
source=https://files.pythonhosted.org/packages/52/73/f1334c29c2af4cd9dba6c7817e61b611bd0215e2eb5565c6064a4de18802/prometheus_client-0.26.0.tar.gz
sha256=04a91bcf94e2cf74a44a1a874d651a2e853ed354b6e822f3b7487751465d5c2b

depends="
    python3
"
makedepends="
    python3
    python3-pip
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

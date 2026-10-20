#!/bin/sh

# python-oslo-metrics: oslo.metrics: OpenStack metrics collection
#
# oslo.metrics 0.17.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-metrics
pkgver=0.17.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.metrics: OpenStack metrics collection"
license="Apache-2.0"
origin=oslo.metrics
repo=saphira
url=https://pypi.org/project/oslo.metrics/
source=https://files.pythonhosted.org/packages/a6/ee/e09d6eb519c497217a17a99b4f5ff131d5360527eb6e600fabd1b2ad5674/oslo_metrics-0.17.0.tar.gz
sha256=3fa3d6d6209efdbdcf88840a2016efa53fa6c1a3e98847e60ded0d91d074216b

depends="
    python3
    python-oslo-utils
    python-oslo-log
    python-oslo-config
    python-prometheus-client
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

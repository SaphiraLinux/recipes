#!/bin/sh

# python-cotyledon: framework for long-running services (oslo threading backend)
#
# cotyledon 2.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
# setuptools_scm present for the setuptools build backend; version
# comes from the sdist metadata, not git.
#
# Required by oslo_service's threading backend (glance-manage and
# service startup import cotyledon; without it every call fails with
# "Unknown backend: 'threading'"). Pure Python + setproctitle.

pkgname=python-cotyledon
pkgver=2.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="cotyledon: framework for defining long-running services"
license="Apache-2.0"
origin=cotyledon
repo=saphira
url=https://pypi.org/project/cotyledon/
source=https://files.pythonhosted.org/packages/de/9e/e7856beede7f8e6c5616ea0b692b279295febbdf301abb48dcd3b05424fe/cotyledon-2.2.0.tar.gz
sha256=5f9dcc4cfb8124e6550119bb4f6fbda8628bbe653804015b76c392fa5f208009

depends="
    python3
    python-setproctitle
    typing-extensions
"
makedepends="
    python3
    python3-pip
    setuptools
    python-setuptools-scm
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
    PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('cotyledon'))"
}

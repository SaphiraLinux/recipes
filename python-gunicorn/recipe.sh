#!/bin/sh

# python-gunicorn: gunicorn: WSGI HTTP server (Keystone WSGI container)
#
# gunicorn 26.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-gunicorn
pkgver=26.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="gunicorn: WSGI HTTP server (Keystone WSGI container)"
license="MIT"
origin=gunicorn
repo=saphira
url=https://pypi.org/project/gunicorn/
source=https://files.pythonhosted.org/packages/6d/b7/a4a3f632f823e432ce6bc65f62961b7980c898c77f075a2f7118cb3846fe/gunicorn-26.0.0.tar.gz
sha256=ca9346f85e3a4aeeb64d491045c16b9a35647abd37ea15efe53080eb8b090baf

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

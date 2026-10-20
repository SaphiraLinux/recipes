#!/bin/sh

# python-pytz: pytz: world timezone definitions (Flask-RESTful)
#
# pytz 2026.3.post1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
#
# pkgver is the apk-valid form of the upstream 2026.3.post1: apk rejects the
# PEP 440 dot-post suffix and uses _p<N> for a patch level, which sorts above
# the base exactly as a post-release does. The vendored archive keeps its
# upstream basename (pytz-2026.3.post1.tar.gz).

pkgname=python-pytz
pkgver=2026.3_p1
pkgrel=1
pkgarch=noarch
pkgdesc="pytz: world timezone definitions (Flask-RESTful)"
license="MIT"
origin=pytz
repo=saphira
url=https://pypi.org/project/pytz/
source=https://files.pythonhosted.org/packages/fb/48/fb042503b6ca6cd271261dc559fd6432f7d8c713153e9ec5c591af4dfc1c/pytz-2026.3.post1.tar.gz
sha256=2211d3fcf9a797d3405cac96ac7f61d80e6a644f72a3309607282fe8a2010c5d

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

#!/bin/sh

# python-xstatic-angular-bootstrap: Angular-Bootstrap 2.5.0 (XStatic packaging standard)
#
# XStatic-Angular-Bootstrap 2.5.0.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-angular-bootstrap
pkgver=2.5.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="Angular-Bootstrap 2.5.0 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Angular-Bootstrap
repo=saphira
url=https://pypi.org/project/XStatic-Angular-Bootstrap/
source=https://files.pythonhosted.org/packages/dc/77/c3efa0b8c7ef6f4b6114b14f43998ca6aaa95aaefeb667bc0cc2b0e58c7d/xstatic_angular_bootstrap-2.5.0.1.tar.gz
sha256=8388d40849ca7c1450bc739dbe7c089c9ad8e46cbd73ee4656eb8c2d077eb55b

depends="
    python3
    python-xstatic
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

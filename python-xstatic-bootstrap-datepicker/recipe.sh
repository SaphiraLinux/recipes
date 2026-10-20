#!/bin/sh

# python-xstatic-bootstrap-datepicker: Bootstrap-Datepicker 1.4.0 (XStatic packaging standard)
#
# XStatic-Bootstrap-Datepicker 1.4.0.1, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-bootstrap-datepicker
pkgver=1.4.0.1
pkgrel=1
pkgarch=noarch
pkgdesc="Bootstrap-Datepicker 1.4.0 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Bootstrap-Datepicker
repo=saphira
url=https://pypi.org/project/XStatic-Bootstrap-Datepicker/
source=https://files.pythonhosted.org/packages/a7/40/8e5ea53d5a3a4ef3b8dde9726d8055bab244164fdf0d9c87f9e575845447/xstatic_bootstrap_datepicker-1.4.0.1.tar.gz
sha256=57780ea466d736c19e966dbe79999e1a5fd6ecfba5235ccfb1d11750987e3736

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

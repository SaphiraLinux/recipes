#!/bin/sh

# python-oslo-reports: oslo.reports library
#
# oslo.reports 3.9.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-reports
pkgver=3.9.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.reports library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=oslo.reports
repo=saphira
url=https://pypi.org/project/oslo.reports/
source=https://files.pythonhosted.org/packages/57/d8/6918517b6703189482522c9384955e237c2e845484b4d1fb8f8c4d8e1777/oslo_reports-3.9.0.tar.gz
sha256=66e0563d5cb5afc0facba08f48906493d44a9a0487d14a3b02b12fb60ed95513

depends="
    python3
    python-jinja2
    python-oslo-config
    python-oslo-i18n
    python-oslo-serialization
    python-oslo-utils
    python-pbr
    python-psutil"

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

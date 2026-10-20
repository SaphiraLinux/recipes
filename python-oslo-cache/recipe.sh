#!/bin/sh

# python-oslo-cache: oslo.cache: OpenStack caching layer
#
# oslo.cache 4.3.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-cache
pkgver=4.3.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.cache: OpenStack caching layer"
license="Apache-2.0"
origin=oslo.cache
repo=saphira
url=https://pypi.org/project/oslo.cache/
source=https://files.pythonhosted.org/packages/e7/19/e89474be0b62e2f61c089ad9c437ddf8fb1fc482c61ca7e7e29e19f0c086/oslo_cache-4.3.0.tar.gz
sha256=c747ada25e20925746da36a208eec50f0d4c310fcaac10b436b69393ee8140fe

depends="
    python3
    python-dogpile-cache
    python-oslo-config
    python-oslo-i18n
    python-oslo-log
    python-oslo-utils
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

#!/bin/sh

# python-cursive: Cursive implements OpenStack-specific validation of digital signatures.
#
# cursive 0.3.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-cursive
pkgver=0.3.1
pkgrel=1
pkgarch=noarch
pkgdesc="Cursive implements OpenStack-specific validation of digital signatures. (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=cursive
repo=saphira
url=https://pypi.org/project/cursive/
source=https://files.pythonhosted.org/packages/ea/6b/b2742129b3f3cf991f623ff7a0b939753172314b1c09aec639b36149e407/cursive-0.3.1.tar.gz
sha256=864f6d2ffc5b3c3e0b27afa350caf1524a5502391fb128adce215e449fb244ab

depends="
    python3
    python-castellan
    python-cryptography
    python-oslo-i18n
    python-oslo-log
    python-oslo-serialization
    python-oslo-utils
    python-pbr"

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

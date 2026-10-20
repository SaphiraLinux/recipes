#!/bin/sh

# python-pyparsing: pyparsing - Classes and methods to define and execute parsing grammars
#
# pyparsing 3.3.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-pyparsing
pkgver=3.3.2
pkgrel=1
pkgarch=noarch
# Disabled: the established native pyparsing-3.3.2-r2 already owns these
# paths (published, newer pkgrel). Depend on pyparsing, not this.
disabled=yes
disabled_reason='superseded by established native pyparsing (same upstream 3.3.2, higher pkgrel); never delete recipes, disable instead'
pkgdesc="pyparsing - Classes and methods to define and execute parsing grammars (OpenStack 2026.2 closure)"
license='MIT'
origin=pyparsing
repo=saphira
url=https://pypi.org/project/pyparsing/
source=https://files.pythonhosted.org/packages/f3/91/9c6ee907786a473bf81c5f53cf703ba0957b23ab84c264080fb5a450416f/pyparsing-3.3.2.tar.gz
sha256=c777f4d763f140633dcb6d8a3eda953bf7a214dc4eff598413c070bcdc117cbc

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-flit-core
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

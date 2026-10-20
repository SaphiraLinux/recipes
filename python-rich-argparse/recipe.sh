#!/bin/sh

# python-rich-argparse: Rich help formatters for argparse and optparse
#
# rich-argparse 1.8.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-rich-argparse
pkgver=1.8.0
pkgrel=1
pkgarch=noarch
pkgdesc="Rich help formatters for argparse and optparse (OpenStack 2026.2 closure)"
license='MIT'
origin=rich-argparse
repo=saphira
url=https://pypi.org/project/rich-argparse/
source=https://files.pythonhosted.org/packages/6a/e5/1064c43203a357d668cd42435f7a15fe6af51512d85b2104fecb937aa861/rich_argparse-1.8.0.tar.gz
sha256=679df3d832fa94ad6e4bdb07ded088cd7ea2dddc58ae9b2b46346a40b06cbc0c

depends="
    python3
    python-rich"

makedepends="
    python3
    python3-pip
    python-hatchling
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

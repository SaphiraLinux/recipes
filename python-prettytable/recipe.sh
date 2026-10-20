#!/bin/sh

# python-prettytable: prettytable: simple ASCII tables (oslo.upgradecheck)
#
# prettytable 3.18.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-prettytable
pkgver=3.18.0
pkgrel=1
pkgarch=noarch
pkgdesc="prettytable: simple ASCII tables (oslo.upgradecheck)"
license="BSD-3-Clause"
origin=prettytable
repo=saphira
url=https://pypi.org/project/prettytable/
source=https://files.pythonhosted.org/packages/81/74/ba08d81e668ccfe8658d7520a307e63c19862c08eb4ccb26f356c5239a7a/prettytable-3.18.0.tar.gz
sha256=439217116152244369caf3d9f1caf2f9fe29b03bd79e88d2928c8e718c95d680

depends="
    python3
    python-wcwidth
"
makedepends="
    python3
    python3-pip
    python-hatchling
    setuptools
    python-hatch-vcs
    wheel
"

recipe_build()
{
    :
}

recipe_install()
{
    # prettytable 3.18.0 declares "Programming Language :: Python :: 3.16",
    # which no released trove-classifiers knows yet, so hatchling's
    # classifier lint rejects it. HATCH_METADATA_CLASSIFIERS_NO_VERIFY is
    # hatchling's own documented escape hatch and skips ONLY that metadata
    # lint; the built package is unchanged (classifiers are cosmetic).
    HATCH_METADATA_CLASSIFIERS_NO_VERIFY=1 \
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

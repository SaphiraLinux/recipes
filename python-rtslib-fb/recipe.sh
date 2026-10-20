#!/bin/sh

# python-rtslib-fb: API for Linux kernel SCSI target (aka LIO)
#
# rtslib-fb 2.2.4, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-rtslib-fb
pkgver=2.2.4
pkgrel=1
pkgarch=noarch
pkgdesc="API for Linux kernel SCSI target (aka LIO) (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=rtslib-fb
repo=saphira
url=https://pypi.org/project/rtslib-fb/
source=https://files.pythonhosted.org/packages/79/32/030eaf69d4f19cac2345a6fab1f18118355f7c9c83d6d84f758b00bbd3d9/rtslib_fb-2.2.4.tar.gz
sha256=0084daa651a72b1cacd0eaaf162725df69b991f501cffe87e0f67e99224a7267

depends="
    python3
    python-pyudev"

makedepends="
    python3
    python3-pip
    python-hatchling
    python-hatch-vcs
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

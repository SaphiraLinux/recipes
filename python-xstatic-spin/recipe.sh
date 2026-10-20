#!/bin/sh

# python-xstatic-spin: Spin 1.2.5 (XStatic packaging standard)
#
# XStatic-Spin 1.2.5.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-spin
pkgver=1.2.5.3
pkgrel=1
pkgarch=noarch
pkgdesc="Spin 1.2.5 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-Spin
repo=saphira
url=https://pypi.org/project/XStatic-Spin/
source=https://files.pythonhosted.org/packages/a0/7a/598e72d65c1fca68aa1a47f62d6dd72ad8aa67ceaaa5a5193afc8ae9ada1/XStatic-Spin-1.2.5.3.tar.gz
sha256=06e889cf3318f08ce74ef888b45d9f1e09017bb8e6d519a299c10a9e6b542642

depends="
    python3
    python-xstatic
"

makedepends="
    python3
    python3-pip
    python-xstatic
    setuptools
    wheel
"

recipe_build()
{
    :
}

recipe_install()
{
    # setup.py reads its name/version from xstatic.pkg.spin at
    # egg_info time. pip's setup.py shim does not reliably keep the
    # source tree importable (observed: xstatic.pkg resolves as an
    # empty namespace, "unknown location"), so pin the absolute
    # source dir on PYTHONPATH: immune to the shim's cwd handling.
    PYTHONPATH="$SRC" python3 -m pip install \
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

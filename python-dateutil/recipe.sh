#!/bin/sh

# python-dateutil: python-dateutil 2.9.0.post0
#
# PyPI python-dateutil 2.9.0.post0, vendored sdist, pip-installed offline
# (--no-deps --no-build-isolation, build backends from the repo).
# Native Saphira recipe; no unpinned network installs at build time.
#
# pkgver is the apk-valid form of the upstream 2.9.0.post0: apk rejects the
# PEP 440 dot-post suffix ("version is invalid") and uses _p<N> for a patch
# level, which sorts above the base exactly as a post-release does. The
# vendored archive keeps its upstream basename (python-dateutil-2.9.0.post0.tar.gz).

pkgname=python-dateutil
pkgver=2.9.0_p0
pkgrel=1
pkgarch=noarch
pkgdesc="python-dateutil Python library"
license="BSD-3-Clause"
origin=python-dateutil
repo=saphira
url=https://pypi.org/project/python-dateutil/
source=https://files.pythonhosted.org/packages/66/c0/0c8b6ad9f17a802ee498c46e004a0eb49bc148f2fd230864601a86dcf6db/python-dateutil-2.9.0.post0.tar.gz
sha256=37dd54208da7e1cd875388217d5e00ebd4179249f90fb72437e91a35459a0ad3

depends="
    python3
    python-six
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

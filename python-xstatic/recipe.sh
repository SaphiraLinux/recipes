#!/bin/sh

# python-xstatic: XStatic base package with minimal support code
#
# XStatic 1.0.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic
pkgver=1.0.3
pkgrel=2
pkgarch=noarch
pkgdesc="XStatic base package with minimal support code (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic
repo=saphira
url=https://pypi.org/project/XStatic/
source=https://files.pythonhosted.org/packages/d6/dd/e448da90f0e72a30546cda9b193893ea2907e7d3a702655c2c3b80c3b97f/XStatic-1.0.3.tar.gz
sha256=402544cc9e179489441054f09c807804e115ea246907de87c0355fb4f5a31268

depends="
    python3
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
    # XStatic 1.0.3 predates PEP 420: its pkg_resources
    # declare-namespace bootstrap (xstatic/__init__.py plus the
    # setuptools nspkg.pth) crashes on Python 3.14
    # ("module_from_spec NoneType has no loader", remainder of the
    # .pth ignored), leaving a poisoned half-registered xstatic
    # module that hides every leaf never installed yet. The whole
    # XStatic tree lives in one site-packages directory, so implicit
    # namespace packages merge it with no bootstrap at all: drop
    # the declare file and any nspkg.pth from the payload.
    rm -f "$PKGDEST"/usr/lib/python3*/site-packages/xstatic/__init__.py
    rm -f "$PKGDEST"/usr/lib/python3*/site-packages/*-nspkg.pth
    [ -z "$(find "$PKGDEST" -name '*nspkg.pth' -o -name '__init__.py' -path '*xstatic*')" ] || {
        echo "ERROR: python-xstatic still ships namespace bootstrap files" >&2
        return 1
    }
}

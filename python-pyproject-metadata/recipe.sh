#!/bin/sh

# python-pyproject-metadata: PEP 621 metadata parser (meson-python requirement)
#
# pyproject-metadata 0.12.1, vendored sdist, installed offline into
# system site-packages. Pure python.

pkgname=python-pyproject-metadata
pkgver=0.12.1
pkgrel=1
pkgarch=noarch
pkgdesc="PEP 621 metadata parser (OpenStack 2026.2 closure)"
license='MIT'
origin=pyproject-metadata
repo=saphira
url=https://pypi.org/project/pyproject-metadata/
source=https://files.pythonhosted.org/packages/4f/76/1cae539918a7b1746d624c2f01560b793c22cd8c081157505bb9bbf0e34d/pyproject_metadata-0.12.1.tar.gz
sha256=8809a4df6fe08279b39a8890669506ed3158e0617855ac9aff098fcbe772ae4c

depends="
    python3
    packaging
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

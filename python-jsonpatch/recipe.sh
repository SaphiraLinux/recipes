#!/bin/sh

# python-jsonpatch: Apply JSON-Patches (RFC 6902)
#
# jsonpatch 1.33, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-jsonpatch
pkgver=1.33
pkgrel=1
pkgarch=noarch
pkgdesc="Apply JSON-Patches (RFC 6902) (OpenStack 2026.2 closure)"
license='BSD-3-Clause'
origin=jsonpatch
repo=saphira
url=https://pypi.org/project/jsonpatch/
source=https://files.pythonhosted.org/packages/42/78/18813351fe5d63acad16aec57f94ec2b70a09e53ca98145589e185423873/jsonpatch-1.33.tar.gz
sha256=9fcd4009c41e6d12348b4a0ff2563ba56a2923a7dfee731d004e212e1ee5030c

depends="
    python3
    python-jsonpointer"

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

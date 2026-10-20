#!/bin/sh

# python-mdurl: Markdown URL utilities
#
# mdurl 0.1.2, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-mdurl
pkgver=0.1.2
pkgrel=1
pkgarch=noarch
pkgdesc="Markdown URL utilities (OpenStack 2026.2 closure)"
license='MIT'
origin=mdurl
repo=saphira
url=https://pypi.org/project/mdurl/
source=https://files.pythonhosted.org/packages/d6/54/cfe61301667036ec958cb99bd3efefba235e65cdeb9c84d24a8293ba1d90/mdurl-0.1.2.tar.gz
sha256=bb413d29f5eea38f31dd4754dd7377d4465116fb207585f97bf925588687c1ba

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

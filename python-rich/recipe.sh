#!/bin/sh

# python-rich: Render rich text, tables, progress bars, syntax highlighting, markdown and more to the terminal
#
# rich 15.0.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-rich
pkgver=15.0.0
pkgrel=1
pkgarch=noarch
pkgdesc="Render rich text, tables, progress bars, syntax highlighting, markdown and more to the terminal (OpenStack 2026.2 closure)"
license='MIT'
origin=rich
repo=saphira
url=https://pypi.org/project/rich/
source=https://files.pythonhosted.org/packages/c0/8f/0722ca900cc807c13a6a0c696dacf35430f72e0ec571c4275d2371fca3e9/rich-15.0.0.tar.gz
sha256=edd07a4824c6b40189fb7ac9bc4c52536e9780fbbfbddf6f1e2502c31b068c36

depends="
    python3
    python-markdown-it-py
    python-pygments"

makedepends="
    python3
    python3-pip
    python-poetry-core
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

#!/bin/sh

# python-markdown-it-py: Python port of markdown-it. Markdown parsing, done right!
#
# markdown-it-py 4.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-markdown-it-py
pkgver=4.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="Python port of markdown-it. Markdown parsing, done right! (OpenStack 2026.2 closure)"
license='MIT'
origin=markdown-it-py
repo=saphira
url=https://pypi.org/project/markdown-it-py/
source=https://files.pythonhosted.org/packages/06/ff/7841249c247aa650a76b9ee4bbaeae59370dc8bfd2f6c01f3630c35eb134/markdown_it_py-4.2.0.tar.gz
sha256=04a21681d6fbb623de53f6f364d352309d4094dd4194040a10fd51833e418d49

depends="
    python3
    python-mdurl"

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

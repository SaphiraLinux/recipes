#!/bin/sh

# python-cmd2: cmd2 - quickly build feature-rich and user-friendly interactive command line applications in Python
#
# cmd2 4.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-cmd2
pkgver=4.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="cmd2 - quickly build feature-rich and user-friendly interactive command line applications in Python (OpenStack 2026.2 closure)"
license='MIT'
origin=cmd2
repo=saphira
url=https://pypi.org/project/cmd2/
source=https://files.pythonhosted.org/packages/ee/41/5c58c7f761eab29df4a633feea7c10044efc7f2fcff9d0925df957a7b2e8/cmd2-4.2.0.tar.gz
sha256=0546543c1ba3c6090ecec33f1373c59627e417b14419629a48176115946fd329

depends="
    python3
    python-prompt-toolkit
    python-pyperclip
    python-rich
    python-rich-argparse"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
    python-setuptools-scm
    python-build
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

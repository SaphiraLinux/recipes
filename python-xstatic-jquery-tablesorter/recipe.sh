#!/bin/sh

# python-xstatic-jquery-tablesorter: JQuery.TableSorter 2.14.5 (XStatic packaging standard)
#
# XStatic-JQuery.TableSorter 2.14.5.3, vendored sdist, installed offline into system
# site-packages. Frontend asset bundle for Horizon; pure data.

pkgname=python-xstatic-jquery-tablesorter
pkgver=2.14.5.3
pkgrel=1
pkgarch=noarch
pkgdesc="JQuery.TableSorter 2.14.5 (XStatic packaging standard) (OpenStack 2026.2 closure)"
license='MIT'
origin=XStatic-JQuery.TableSorter
repo=saphira
url=https://pypi.org/project/XStatic-JQuery.TableSorter/
source=https://files.pythonhosted.org/packages/24/3f/f90c64b3845c4f84ba136e645626341bcb43ba983882f18ed26ad968bd34/xstatic_jquery_tablesorter-2.14.5.3.tar.gz
sha256=e8a4f4900992fe87e2a41167a07fab0aaab39ef194090f58e0083892dc4bcc34

depends="
    python3
    python-xstatic
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

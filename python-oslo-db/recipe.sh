#!/bin/sh

# python-oslo-db: oslo.db: OpenStack database access layer
#
# oslo.db 18.1.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-db
pkgver=18.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.db: OpenStack database access layer"
license="Apache-2.0"
origin=oslo.db
repo=saphira
url=https://pypi.org/project/oslo.db/
source=https://files.pythonhosted.org/packages/33/dd/3ed5c23e1f92882664fc65c55cd6b3756b4679f93289760d567df0685561/oslo_db-18.1.1.tar.gz
sha256=5239ba059b94c381c61b5abe607adcd15eaee8df115deaddb8a36dcb366e44fa

depends="
    python3
    python-alembic
    python-debtcollector
    python-oslo-i18n
    python-oslo-config
    python-oslo-utils
    python-sqlalchemy
    python-stevedore
    python-testresources
    python-testscenarios
    python-pbr
"
makedepends="
    python3
    python3-pip
    python-pbr
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

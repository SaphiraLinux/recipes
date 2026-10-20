#!/bin/sh

# python-alembic: alembic: database migrations for SQLAlchemy
#
# alembic 1.19.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
# tomli is a python_version<'3.11' marker dependency; not needed on 3.14.

pkgname=python-alembic
pkgver=1.19.1
pkgrel=1
pkgarch=noarch
pkgdesc="alembic: database migrations for SQLAlchemy"
license="MIT"
origin=alembic
repo=saphira
url=https://pypi.org/project/alembic/
source=https://files.pythonhosted.org/packages/16/2b/e4153978368de59918115c9e01d3ebf58a558a7285efa7e960c383c4b59a/alembic-1.19.1.tar.gz
sha256=e0fca0518118c78acc493e31bcb5402f190057aaf6df8b5b95ce94c4789cf648

depends="
    python3
    python-mako
    python-sqlalchemy
    typing-extensions
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

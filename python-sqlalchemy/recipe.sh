#!/bin/sh

# python-sqlalchemy: SQLAlchemy 2.0 ORM/SQL toolkit (C extensions + asyncio/greenlet preserved)
#
# SQLAlchemy 2.0.52, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
# Pinned to the OpenStack 2026.2 upper-constraints (SQLAlchemy===2.0.52). The oslo.db [asyncio] extra requires greenlet.
#
# The Cython C extensions (sqlalchemy.cyextension.*) are REQUIRED, not
# optional: upstream builds them only when Cython is importable and treats
# them as optional unless REQUIRE_SQLALCHEMY_CEXT is set, so a build root
# without Cython silently produced a pure-Python payload under an
# arch-specific package (the r1 defect: every python-sqlalchemy-2.0.52-r1
# APK carried no .so). Cython is declared, REQUIRE_SQLALCHEMY_CEXT=1 makes
# a failed build fatal, and recipe_install asserts the staged .so exists.

pkgname=python-sqlalchemy
pkgver=2.0.52
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="SQLAlchemy 2.0 ORM/SQL toolkit (compiled cyextension + asyncio/greenlet)"
license="MIT"
origin=SQLAlchemy
repo=saphira
url=https://pypi.org/project/SQLAlchemy/
source=https://files.pythonhosted.org/packages/3b/21/77b4c147963073040dc3c3a5cb7a8c3001a1893c0209432cb77f9df836aa/sqlalchemy-2.0.52.tar.gz
sha256=5e2d46356ac2ccb7d268ab6c2319ac6a2b42f1b8d5fd8bd3d46855cd82abee97

depends="
    python3
    typing-extensions
    python-greenlet
"
makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    wheel
    gcc
    cython
"

recipe_build()
{
    :
}

recipe_install()
{
    # REQUIRE_SQLALCHEMY_CEXT=1: upstream's own switch that makes the
    # Cython extensions mandatory instead of a silent pure-Python fallback.
    REQUIRE_SQLALCHEMY_CEXT=1 \
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

    # The compiled cyextension objects MUST be in the payload.
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/sqlalchemy/cyextension/*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-sqlalchemy staged payload is missing the compiled" \
             "sqlalchemy/cyextension/*.so (Cython + REQUIRE_SQLALCHEMY_CEXT" \
             "should have made it mandatory)" >&2
        return 1
    }
}

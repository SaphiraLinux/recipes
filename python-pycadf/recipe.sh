#!/bin/sh

# python-pycadf: pycadf: CADF event model for OpenStack auditing
#
# pycadf 4.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
#
# pycadf's pyproject declares [tool.setuptools.data-files]
# "etc/pycadf" = [<per-service CADF audit maps>]. The destination is
# prefix-relative, so --prefix /usr would stage them at usr/etc/pycadf, a
# prefix-derived root makepkg refuses. They belong at /etc/pycadf and are
# relocated there in recipe_install.

pkgname=python-pycadf
pkgver=4.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="pycadf: CADF event model for OpenStack auditing"
license="Apache-2.0"
origin=pycadf
repo=saphira
url=https://pypi.org/project/pycadf/
source=https://files.pythonhosted.org/packages/24/e7/dc9d02c4c2fe2570552273c778de7fdab86993ad2bea1bac82f576dd1218/pycadf-4.1.0.tar.gz
sha256=7f9be03e774ce3cc97675aac7c807c017cad6775961da7e9508f75bcc9f43267

depends="
    python3
    python-oslo-config
    python-oslo-serialization
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

    # Move the prefix-relative data-files destination to the correct FHS
    # path, and refuse a payload that lost them.
    if [ -d "$PKGDEST/usr/etc/pycadf" ]; then
        install -d -m 0755 "$PKGDEST/etc"
        mv "$PKGDEST/usr/etc/pycadf" "$PKGDEST/etc/pycadf"
        rmdir "$PKGDEST/usr/etc" 2>/dev/null || true
    fi
    [ -d "$PKGDEST/etc/pycadf" ] || {
        echo "ERROR: python-pycadf payload is missing the etc/pycadf audit maps" >&2
        return 1
    }
}

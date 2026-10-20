#!/bin/sh

# python-os-brick: OpenStack Cinder brick library for managing local volume attaches
#
# os-brick 7.1.1, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.
#
# The sdist declares etc/os-brick as a data-files destination, which is
# prefix-relative: --prefix /usr would stage usr/etc/os-brick, a
# prefix-derived root makepkg refuses (pycadf precedent). The
# rootwrap filters belong at /etc/os-brick and are relocated there.

pkgname=python-os-brick
pkgver=7.1.1
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack Cinder brick library for managing local volume attaches (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=os-brick
repo=saphira
url=https://pypi.org/project/os-brick/
source=https://files.pythonhosted.org/packages/ac/6b/6354e1a75d4791122720b0d01f50fc7b0b5c8a7e38b3481cb72ec42dd089/os_brick-7.1.1.tar.gz
sha256=a5034b9f57e5640dc166ae5160cd59e17f3737b376d85b949ba8329c30f555c8

depends="
    python3
    python-oslo-concurrency
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-log
    python-oslo-privsep
    python-oslo-serialization
    python-oslo-service
    python-oslo-utils
    python-pbr
    python-psutil
    python-requests
    python-tenacity"

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
    if [ -d "$PKGDEST/usr/etc/os-brick" ]; then
        install -d -m 0755 "$PKGDEST/etc"
        mv "$PKGDEST/usr/etc/os-brick" "$PKGDEST/etc/os-brick"
        rmdir "$PKGDEST/usr/etc" 2>/dev/null || true
    fi
    [ -f "$PKGDEST/etc/os-brick/rootwrap.d/os-brick.filters" ] || {
        echo "ERROR: python-os-brick lost etc/os-brick/rootwrap.d/os-brick.filters" >&2
        return 1
    }
}

#!/bin/sh

# python-libvirt: libvirt Python bindings (nova KVM driver requirement)
#
# libvirt-python 12.6.0, vendored sdist, links the native libvirt
# 12.6.0 (version-locked: bindings must match the daemon). Compiled
# extension (setuptools); asserted staged below.

pkgname=python-libvirt
pkgver=12.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="libvirt Python bindings (OpenStack 2026.2 closure)"
license='LGPL-2.0-or-later'
origin=libvirt-python
repo=saphira
url=https://pypi.org/project/libvirt-python/
source=https://files.pythonhosted.org/packages/1d/18/b64bc6c6739405fddd451f78e756c17411d309265ec748683b806bd1dd47/libvirt_python-12.6.0.tar.gz
sha256=f390abff81d4afd6c33157ade82912863b87de9c35172e9b0c9f0dfcdc09b139

depends="
    python3
    libvirt
"

makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    wheel
    gcc
    pkgconf
    libvirt
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
    # compiled extension must actually be staged (no silent fallback:
    # nova-compute checks for working libvirt bindings at driver init)
    staged=$(find "$PKGDEST" -name 'libvirtmod.*.so' | head -1)
    [ -n "$staged" ] || {
        echo "ERROR: staged payload is missing the compiled libvirt extension" >&2
        return 1
    }
}

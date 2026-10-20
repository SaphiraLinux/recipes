#!/bin/sh

# python-glance-store: OpenStack Image Service Store Library
#
# glance-store 5.7.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-glance-store
pkgver=5.7.0
pkgrel=1
pkgarch=noarch
pkgdesc="OpenStack Image Service Store Library (OpenStack 2026.2 closure)"
license='Apache-2.0'
origin=glance-store
repo=saphira
url=https://pypi.org/project/glance-store/
source=https://files.pythonhosted.org/packages/a5/cb/010db963d0281ded33053a73bb7cfc9bed1fe8dc75aae7fc7257ad5bd98f/glance_store-5.7.0.tar.gz
sha256=7c7906b01e32264a7fc4ab6e690eaa3833d3b54cfb0f727e1a069ace7a0fd856

depends="
    python3
    python-futurist
    python-jsonschema
    python-keystoneauth1
    python-keystoneclient
    python-oslo-concurrency
    python-oslo-config
    python-oslo-i18n
    python-oslo-serialization
    python-oslo-utils
    python-requests
    python-retrying
    python-stevedore"

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

    # setup.cfg data_files target etc/glance (rootwrap policy for the
    # cinder store backend); pip prefixes that to usr/etc. The filters
    # are privilege-boundary policy the stores need, so install them
    # explicitly to /etc/glance (this package owns rootwrap.conf and
    # rootwrap.d only) and drop the pip copy.
    install -d -m 0755 "$PKGDEST/etc/glance/rootwrap.d"
    install -m 0644 "$SRC/etc/glance/rootwrap.conf" \
        "$PKGDEST/etc/glance/rootwrap.conf"
    install -m 0644 "$SRC/etc/glance/rootwrap.d/glance_cinder_store.filters" \
        "$PKGDEST/etc/glance/rootwrap.d/"
    rm -rf "$PKGDEST/usr/etc"
}

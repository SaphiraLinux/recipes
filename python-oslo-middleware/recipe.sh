#!/bin/sh

# python-oslo-middleware: oslo.middleware: OpenStack WSGI middleware
#
# oslo.middleware 8.2.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-oslo-middleware
pkgver=8.2.0
pkgrel=1
pkgarch=noarch
pkgdesc="oslo.middleware: OpenStack WSGI middleware"
license="Apache-2.0"
origin=oslo.middleware
repo=saphira
url=https://pypi.org/project/oslo.middleware/
source=https://files.pythonhosted.org/packages/f5/24/6e725c446a4e187141dde846dbe96c11c0e24916055fb5bd58955e81bb93/oslo_middleware-8.2.0.tar.gz
sha256=dc53a609c59bb3d92f7364d9b6db8f704e672f5b7ea904c5824ccc1dc189b92b

depends="
    python3
    python-bcrypt
    python-jinja2
    python-oslo-config
    python-oslo-context
    python-oslo-i18n
    python-oslo-utils
    python-statsd
    python-stevedore
    python-webob
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

#!/bin/sh

# python-redis: Python client for Redis database and key-value store
#
# redis 8.1.0, vendored sdist, installed offline into system
# site-packages. --no-index (no index access), --no-build-isolation
# (no isolation downloads), explicit native build dependencies.

pkgname=python-redis
pkgver=8.1.0
pkgrel=1
pkgarch=noarch
pkgdesc="Python client for Redis database and key-value store (OpenStack 2026.2 closure)"
license='MIT'
origin=redis
repo=saphira
url=https://pypi.org/project/redis/
source=https://files.pythonhosted.org/packages/a8/99/604f0b666d4c616d891cf77ebb9db6bb21601344c051aebf1b72b9ff915f/redis-8.1.0.tar.gz
sha256=6e1a19beef9225c83efd689c7e6b7da2d5215b1f42cd13b7fc3714d0a09c7b25

depends="
    python3
"

makedepends="
    python3
    python3-pip
    python-hatchling
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

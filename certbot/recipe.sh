#!/bin/sh

pkgname=certbot
pkgver=5.7.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Let's Encrypt / ACME client (certbot)"
license="Apache-2.0"
origin=certbot
repo=saphira
url=https://pypi.org/project/certbot/
source=https://files.pythonhosted.org/packages/2d/1a/eb1d1ff8682fbfcf7089f5e0cad80c259646f44cc85ce9d3533af901b3e6/certbot-5.7.0.tar.gz
sha256=c896a0aa3fe1fa1e344002d4a24a5934889a88b8759f41a22b4dcfe5a8e27b94

# Requires cryptography>=43.0.0 at runtime (via acme, not yet ported).
depends="
    python3
    acme
    python-configargparse
    python-configobj
    python-cryptography
    python-distro
    python-josepy
    python-parsedatetime
    python-pyrfc3339
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
    # The 5.7.0 sdist is a src-layout package (src/certbot/): install from
    # the extracted source root (pyproject.toml), not from a package
    # subdirectory.
    python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
    install -d -m 0755 "$PKGDEST/etc/letsencrypt" \
        "$PKGDEST/var/lib/letsencrypt" \
        "$PKGDEST/var/log/letsencrypt"
    # Daily renewal via the house cron convention: dcron's root crontab
    # runs /usr/sbin/run-cron /etc/cron.daily, so an executable file here
    # is the timer. certbot renews inside its 30-day pre-expiry window and
    # runs the deploy hooks for each renewed lineage.
    install -D -m 0755 "$RECIPE_DIR/files/certbot-renew" \
        "$PKGDEST/etc/cron.daily/certbot-renew"
}

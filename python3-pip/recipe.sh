#!/bin/sh

pkgname=python3-pip
pkgver=25.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python package installer"
license="MIT"
origin=python3-pip
repo=saphira
url=https://pypi.org/project/pip/
source=https://files.pythonhosted.org/packages/20/16/650289cd3f43d5a2fadfd98c68bd1e1e7f2550a1a5326768cddfbcedb2c5/pip-25.2.tar.gz
sha256=578283f006390f85bb6282dffb876454593d637f5d1be494b5202ce4877e71f2

depends="
    python3
"

makedepends="
    python3
"

recipe_build()
{
    :
}

recipe_install()
{
    site=$PKGDEST/usr/lib/python3.14/site-packages
    install -d -m 0755 "$site" "$PKGDEST/usr/bin"
    cp -a "$SRC/src/pip" "$site/pip"
    install -d -m 0755 "$site/pip-25.2.dist-info"
    printf '%s\n' \
        'Metadata-Version: 2.1' \
        'Name: pip' \
        'Version: 25.2' \
        > "$site/pip-25.2.dist-info/METADATA"
    printf '%s\n' \
        '[console_scripts]' \
        'pip = pip._internal.cli.main:main' \
        'pip3 = pip._internal.cli.main:main' \
        > "$site/pip-25.2.dist-info/entry_points.txt"
    printf '%s\n' \
        '#!/usr/bin/python3' \
        'import sys' \
        'from pip._internal.cli.main import main' \
        'sys.exit(main())' \
        > "$PKGDEST/usr/bin/pip3"
    chmod 0755 "$PKGDEST/usr/bin/pip3"
    ln -s pip3 "$PKGDEST/usr/bin/pip"
}

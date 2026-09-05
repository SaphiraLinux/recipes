#!/bin/sh

pkgname=wheel
pkgver=0.47.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python wheel packaging utility"
license="MIT"
origin=wheel
repo=saphira
url=https://pypi.org/project/wheel/
source=https://files.pythonhosted.org/packages/39/62/75f18a0f03b4219c456652c7780e4d749b929eb605c098ce3a5b6b6bc081/wheel-0.47.0.tar.gz
sha256=cc72bd1009ba0cf63922e28f94d9d83b920aa2bb28f798a31d0691b02fa3c9b3

depends="
    python3
    packaging
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
    dist_info=$site/wheel-0.47.0.dist-info
    install -d -m 0755 "$site" "$dist_info/licenses" \
        "$PKGDEST/usr/bin"
    cp -a "$SRC/src/wheel" "$site/"
    install -m 0644 "$SRC/PKG-INFO" "$dist_info/METADATA"
    install -m 0644 "$SRC/LICENSE.txt" \
        "$dist_info/licenses/LICENSE.txt"
    printf '%s\n' \
        'Wheel-Version: 1.0' \
        'Generator: Saphira Linux' \
        'Root-Is-Purelib: true' \
        'Tag: py3-none-any' \
        > "$dist_info/WHEEL"
    printf '%s\n' \
        '[console_scripts]' \
        'wheel = wheel._commands:main' \
        '[distutils.commands]' \
        'bdist_wheel = wheel.bdist_wheel:bdist_wheel' \
        > "$dist_info/entry_points.txt"
    printf '%s\n' \
        '#!/usr/bin/python3' \
        'from wheel._commands import main' \
        'raise SystemExit(main())' \
        > "$BUILDDIR/wheel"
    install -m 0755 "$BUILDDIR/wheel" "$PKGDEST/usr/bin/wheel"
}

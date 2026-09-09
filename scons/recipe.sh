#!/bin/sh

pkgname=scons
pkgver=4.11.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Software construction tool (SCons build engine)"
license="MIT"
origin=scons
repo=saphira
url=https://scons.org/
# Pure-Python build tool, first needed by the gpsd recipe. pip install
# from the sdist with no build isolation (same pattern as setuptools):
# $SRC is the builder-extracted, sha256-verified tree on every path.
vendor=https://files.pythonhosted.org/packages/42/b9/b7a5c88f348a0c34594d88100872c55fa1cae863ccb222c1c438341b5503/scons-4.11.1.tar.gz
sha256=4210d1a80a62e986029208117991b6347ccaaaab37b67463a3ff31ee065dc487

depends="
    python3
"

makedepends="
    python3
    python3-pip
"

recipe_build()
{
    :
}

recipe_install()
{
	# Local sdist wins when present (verified, never re-downloaded);
	# otherwise install from the builder-extracted $SRC. The builder
	# pre-extracted the fetch to $SRC, so a local archive replaces the
	# tree wholesale (find -delete never removes $SRC itself).
	SBALL="$RECIPE_DIR/files/scons-4.11.1.tar.gz"
	if [ -f "$SBALL" ]; then
		echo "$sha256  $SBALL" | sha256sum -c -
		find "$SRC" -mindepth 1 -delete
		tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$SBALL"
	fi
	PYTHONPATH="$SRC:/usr/lib/python3.14/site-packages" \
        python3 -m pip install \
        --no-deps \
        --no-build-isolation \
        --no-compile \
        --root "$PKGDEST" \
        --prefix /usr \
        "$SRC"
    # Deterministic interpreter for the console scripts regardless of
    # which python3 spelling pip saw in the sandbox.
    sed -i '1s|^#!.*|#!/usr/bin/python3|' "$PKGDEST"/usr/bin/scons*
}

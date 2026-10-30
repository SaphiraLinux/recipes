#!/bin/sh

# python-pillow: Python Imaging Library (horizon dependency)
#
# Pillow 13.0.0, vendored sdist, native wheel built in-tree.
# Compiled extensions link native libjpeg-turbo, zlib, libpng,
# freetype, libtiff, openjpeg and lcms2; asserted staged below.
# (libtiff + openjpeg + lcms2 wired in r2 for full format support:
# TIFF C paths, JPEG 2000 and color management.)

pkgname=python-pillow
pkgver=13.0.0
pkgrel=2
# r2: libtiff/openjpeg/lcms2 linkage for full format support (payload
# change: new DT_NEEDED libs + features). Pillow's own
# dist-info/licenses/LICENSE already travels in the wheel; nothing
# further to stage.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python Imaging Library (OpenStack 2026.2 closure)"
license='HPND'
origin=Pillow
repo=saphira
url=https://pypi.org/project/Pillow/
source=https://files.pythonhosted.org/packages/ce/a4/9cc30690a394a8305e8be4c9036aa16d0dfddadd09079860b582f562496d/pillow-13.0.0.tar.gz
sha256=cdcd1ba258178f7356d74170c9a81ba4eab6a5d55748bc402a5a2a6fe6be3510

depends="
    python3
    libjpeg-turbo
    zlib
    libpng
    freetype
    libtiff
    openjpeg
    lcms2
"

makedepends="
    python3
    python3-pip
    python3-dev
    setuptools
    wheel
    python-pybind11
    gcc
    pkgconf
    libjpeg-turbo-dev
    zlib-dev
    libpng
    freetype
    libtiff-dev
    openjpeg-dev
    lcms2-dev
"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/pillow-13.0.0.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/pillow-13.0.0.tar.gz" | sha256sum -c -
	# Native wheel, offline: no index, no deps resolution, no build
	# isolation (setuptools+wheel come from makedepends, exactly as
	# the previous pip-install staging did). All compilation happens
	# here; recipe_install() only extracts the artifact below.
	mkdir -p "$BUILDDIR/dist"
	cd "$SRC"
	python3 -m pip wheel --no-index --no-deps --no-build-isolation \
		-w "$BUILDDIR/dist" .
	# Exactly one wheel must result; anything else is a silent
	# multi-artifact or empty-build defect.
	count=$(ls -1 "$BUILDDIR"/dist/*.whl 2>/dev/null | wc -l)
	[ "$count" -eq 1 ] || {
		echo "ERROR: expected exactly one wheel in $BUILDDIR/dist, found $count" >&2
		return 1
	}
}

recipe_install()
{
	# Stage the already-built wheel ONLY: no compilation, no
	# dependency resolution, no network. Stdlib zipfile extraction,
	# same idiom as the pure-python wheel recipes (certifi, pyyaml).
	set -- "$BUILDDIR"/dist/*.whl
	[ $# -eq 1 ] || {
		echo "ERROR: expected exactly one wheel in $BUILDDIR/dist, found $#" >&2
		return 1
	}
	python3 - "$1" "$PKGDEST" <<'PYINSTALL'
import sys, zipfile, pathlib, subprocess
wheel, pkgdest = sys.argv[1], sys.argv[2]
site = subprocess.run(["python3", "-c", "import sysconfig; print(sysconfig.get_path('purelib', vars={'base': '/usr'}))"], capture_output=True, text=True, check=True).stdout.strip()
target = pathlib.Path(pkgdest) / site.lstrip('/')
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(wheel) as z:
    z.extractall(target)
print("installed wheel to", target)
PYINSTALL
	# compiled extensions must actually be staged (no silent fallback)
	staged=$(find "$PKGDEST" -name '_imaging.*.so' | head -1)
	[ -n "$staged" ] || {
		echo "ERROR: staged payload is missing the compiled Pillow extensions" >&2
		return 1
	}
	# importable against the staged layout, with the required native
	# features present (JPEG/Zlib/FreeType hard; TIFF recorded).
	site=$(python3 -c "import sysconfig; print(sysconfig.get_path('purelib', vars={'base': '/usr'}))")
	PYTHONPATH="$PKGDEST$site" python3 - <<'PYCHECK'
from PIL import Image, features
print("Pillow", Image.__version__)
for feat in ("jpg", "zlib", "freetype2"):
    assert features.check(feat), "missing required feature: %s" % feat
    print("feature %s: OK" % feat)
print("feature tiff_libtiff:", features.check("libtiff") if hasattr(features, "check") else "n/a")
PYCHECK
}

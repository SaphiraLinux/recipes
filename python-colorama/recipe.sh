#!/bin/sh
pkgname=python-colorama
pkgver=0.4.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Cross-platform coloured terminal text (Python module)'
license='BSD-3-Clause'
origin=colorama
repo=saphira
url=https://pypi.org/project/colorama/
# Pure-Python wheel, vendored. Needed by me-analyzer.
source=https://files.pythonhosted.org/packages/d1/d6/3965ed04c63042e047cb6a3e6ed1a63a35087b6a609aa3a15ed8ac56c221/colorama-0.4.6-py2.py3-none-any.whl
sha256=4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6

depends="python3"
makedepends="
    python3
    python3-pip
    setuptools
    unzip
    wheel
"

recipe_build()
{
	:
}

recipe_install()
{
	python3 -m pip install --no-deps --no-build-isolation --no-compile \
		--root "$PKGDEST" --prefix /usr \
		"$RECIPE_DIR/files/colorama-0.4.6-py2.py3-none-any.whl"
}

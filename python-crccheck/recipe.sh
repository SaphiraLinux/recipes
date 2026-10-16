#!/bin/sh
pkgname=python-crccheck
pkgver=1.3.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='CRC calculation library (Python module)'
license='MIT'
origin=crccheck
repo=saphira
url=https://pypi.org/project/crccheck/
# Pure-Python wheel, vendored. Needed by me-analyzer.
source=https://files.pythonhosted.org/packages/01/b5/68a9054be852e61f31de1be4e8d95802646b93344ce17c2380a1748706fa/crccheck-1.3.1-py3-none-any.whl
sha256=1680c9a7bb1ca4bec45fa19b8ca64319f10d2ce4eb8b0d25d51cb99a20ca0108

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
		"$RECIPE_DIR/files/crccheck-1.3.1-py3-none-any.whl"
}

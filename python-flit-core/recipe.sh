#!/bin/sh

pkgname=python-flit-core
pkgver=3.12.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PEP 517 build backend for pure-python packages (flit_core)"
license="MIT"
origin=flit_core
repo=saphira
url=https://pypi.org/project/flit-core/
# Bootstrap artifact: flit_core's build backend is flit_core itself
# (self-hosting), so the pinned upstream wheel is the seed source; every
# later version can be rebuilt from sdist once this exists.

depends="python3"
makedepends="python3 python3-pip"

recipe_build() {
	# Local bootstrap artifact: verify the pinned upstream wheel bytes.
	echo "e7a0304069ea895172e3c7bb703292e992c5d1555dd1233ab7b5621b5b69e62c  $RECIPE_DIR/files/flit_core-3.12.0-py3-none-any.whl" | sha256sum -c -
}

recipe_install() {
	python3 -m pip install \
		--no-deps \
		--no-compile \
		--root "$PKGDEST" \
		--prefix /usr \
		"$RECIPE_DIR/files/flit_core-3.12.0-py3-none-any.whl"
}

#!/bin/sh

pkgname=python-hatchling
pkgver=1.29.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PEP 517 build backend (extensible, standards-compliant)"
license="MIT"
origin=hatchling
repo=saphira
url=https://pypi.org/project/hatchling/
# Bootstrap artifact: flit_core's build backend is flit_core itself
# (self-hosting), so the pinned upstream wheel is the seed source; every
# later version can be rebuilt from sdist once this exists.

depends="
    python3
    packaging
    python-pathspec
    python-pluggy
    python-trove-classifiers
"
makedepends="python3 python3-pip"

recipe_build() {
	# Local bootstrap artifact: verify the pinned upstream wheel bytes.
	echo "50af9343281f34785fab12da82e445ed987a6efb34fd8c2fc0f6e6630dbcc1b0  $RECIPE_DIR/files/hatchling-1.29.0-py3-none-any.whl" | sha256sum -c -
}

recipe_install() {
	python3 -m pip install \
		--no-deps \
		--no-compile \
		--root "$PKGDEST" \
		--prefix /usr \
		"$RECIPE_DIR/files/hatchling-1.29.0-py3-none-any.whl"
}

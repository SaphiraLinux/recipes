#!/bin/sh

pkgname=python-poetry-core
pkgver=2.4.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PEP 517 build backend for poetry-style projects"
license="MIT"
origin=poetry.core
repo=saphira
url=https://pypi.org/project/poetry-core/
# Bootstrap artifact: poetry-core's build backend is poetry-core itself
# (self-hosting), so the pinned upstream wheel is the seed source.

depends="python3"
makedepends="python3 python3-pip"

recipe_build() {
	# Local bootstrap artifact: verify the pinned upstream wheel bytes.
	echo "acf06f9537cd2625bdaec926d95d90b557ba15353bc71d27a3a8a441042b5316  $RECIPE_DIR/files/poetry_core-2.4.1-py3-none-any.whl" | sha256sum -c -
}

recipe_install() {
	python3 -m pip install \
		--no-deps \
		--no-compile \
		--root "$PKGDEST" \
		--prefix /usr \
		"$RECIPE_DIR/files/poetry_core-2.4.1-py3-none-any.whl"
}

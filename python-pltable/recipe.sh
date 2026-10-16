#!/bin/sh
pkgname=python-pltable
pkgver=1.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Tabular text-table library (Python module, ME Analyzer dependency)'
license='BSD-3-Clause'
origin=pltable
repo=saphira
url=https://github.com/platomav/PLTable
# Setuptools sdist, vendored; pip-installed offline like python-pathspec.
# Needed by me-analyzer (platomav's own table module).
source=https://files.pythonhosted.org/packages/53/b9/0276a2c7699255c9a8e459b093db4414162607dcf42636c0bbe4be1bf8e4/PLTable-1.1.0.tar.gz
sha256=dc8eb7cb9721a7090dc7a5976fbec7d3ef6b82a61f86c3b98700571a3f10401a

depends="python3"
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
	python3 -m pip install --no-deps --no-build-isolation --no-compile \
		--root "$PKGDEST" --prefix /usr "$SRC"
}

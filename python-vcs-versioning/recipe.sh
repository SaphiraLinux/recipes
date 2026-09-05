#!/bin/sh

pkgname=python-vcs-versioning
pkgver=2.3.4
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="VCS tag/version parsing (setuptools_scm successor)"
license="MIT"
origin=vcs-versioning
repo=saphira
url=https://pypi.org/project/vcs-versioning/
source=https://files.pythonhosted.org/packages/a0/00/c883501b0c55b7d0ec33e67813e9a38563ea84bfecebce9b3347fa52d845/vcs_versioning-2.3.4.tar.gz
sha256=f3443da15a34a32755b04324e33c6166add300c7661f45902225190c9337f711

depends="python3
    packaging"
makedepends="
    python3
    python3-pip
    setuptools
"

recipe_build() {
	:
}

recipe_install() {
	python3 -m pip install 		--no-deps 		--no-build-isolation 		--no-compile 		--root "$PKGDEST" 		--prefix /usr 		"$SRC"
}

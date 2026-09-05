#!/bin/sh

pkgname=python-hatch-vcs
pkgver=0.5.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Hatchling build hook for versions from VCS tags"
license="MIT"
origin=hatch_vcs
repo=saphira
url=https://pypi.org/project/hatch-vcs/
source=https://files.pythonhosted.org/packages/6b/b0/4cc743d38adbee9d57d786fa496ed1daadb17e48589b6da8fa55717a0746/hatch_vcs-0.5.0.tar.gz
sha256=0395fa126940340215090c344a2bf4e2a77bcbe7daab16f41b37b98c95809ff9

depends="
    python3
    python-hatchling
    python-setuptools-scm
"
makedepends="python3 python3-pip python-hatchling"

recipe_build() {
	:
}

recipe_install() {
	python3 -m pip install \
		--no-deps \
		--no-build-isolation \
		--no-compile \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"
}

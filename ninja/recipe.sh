#!/bin/sh

pkgname=ninja
pkgver=1.13.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Small build system with a focus on speed"
license="Apache-2.0"
origin=ninja
repo=main
url=https://ninja-build.org/
source=https://github.com/ninja-build/ninja/archive/refs/tags/v${pkgver}.tar.gz
sha256=974d6b2f4eeefa25625d34da3cb36bdcebe7fbce40f4c16ac0835fd1c0cbae17

depends=""

makedepends="
    gcc
    python3
"

recipe_build()
{
	python3 "$SRC/configure.py" --bootstrap
	./ninja --version
}

recipe_install()
{
	install -D -m 0755 ninja "$PKGDEST/usr/bin/ninja"
}

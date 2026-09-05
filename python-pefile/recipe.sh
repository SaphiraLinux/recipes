#!/bin/sh

pkgname=python-pefile
pkgver=2024.8.26
pkgrel=2
pkgarch=noarch
pkgdesc="Python library for PE files"
license="MIT"
origin=pefile
repo=main
url=https://github.com/erocarrera/pefile
source=https://files.pythonhosted.org/packages/source/p/pefilE/pefile-${pkgver}.tar.gz
sha256=3ff6c5d8b43e8c37bb6e6dd5085658d658a7a0bdcd20b6a07b1fcfc1c4e9d632

depends="
    python3
"

makedepends="
    python3
    python3-pip
"

recipe_build()
{
	:
}

recipe_install()
{
	python3 -m pip install \
		--ignore-installed \
		--no-deps \
		--no-cache-dir \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"
}

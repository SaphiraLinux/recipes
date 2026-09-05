#!/bin/sh

pkgname=python-jinja2
pkgver=3.1.6
pkgrel=2
pkgarch=noarch
pkgdesc="Python template engine"
license="BSD-3-Clause"
origin=jinja2
repo=main
url=https://jinja.palletsprojects.com/
source=https://files.pythonhosted.org/packages/source/J/Jinja2/jinja2-${pkgver}.tar.gz
sha256=0137fb05990d35f1275a587e9aee6d56da821fc83491a0fb838183be43f66d6d

depends="
    python3
    python-markupsafe
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

#!/bin/sh

pkgname=docbook-xml
pkgver=4.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="XML DTD for computer documentation"
license=MIT
origin=docbook-xml
repo=main
url=https://www.oasis-open.org/docbook/
source=https://www.oasis-open.org/docbook/xml/4.5/docbook-xml-4.5.zip
sha256=4e4e037a2b83c98c6c94818390d4bdd3f6e10f6ec62dd79188594e26190dc7b4

depends="
    xmlcatmgr
"
makedepends="
    unzip
"
subpackages=""

recipe_build()
{
	:
}

recipe_install()
{
	install -d "$PKGDEST/usr/share/xml/docbook/$pkgver"
	cp -a "$SRC"/. "$PKGDEST/usr/share/xml/docbook/$pkgver/"

	install -d "$PKGDEST/usr/share/xml/catalogs"
	install -m 644 "$RECIPE_DIR/files/docbook-xml.conf" \
		"$PKGDEST/usr/share/xml/catalogs/docbook-xml.conf"
	install -d "$PKGDEST/etc/xml"
	install -m 644 "$RECIPE_DIR/files/catalog" "$PKGDEST/etc/xml/catalog"
}

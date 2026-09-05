#!/bin/sh

pkgname=docbook-xsl-nons
pkgver=1.79.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="DocBook XSL stylesheets"
license=MIT
origin=docbook-xsl-nons
repo=main
url=https://docbook.org
source=https://github.com/docbook/xslt10-stylesheets/releases/download/release/${pkgver}/docbook-xsl-nons-${pkgver}.tar.bz2
sha256=ee8b9eca0b7a8f89075832a2da7534bce8c5478fc8fc2676f512d5d87d832102

depends="
    docbook-xml
    libxml2
    xmlcatmgr
"

makedepends=""
subpackages=""

recipe_build()
{
	:
}

recipe_install()
{
	install -d "$PKGDEST/usr/share/xsl-nons/docbook"
	install -m 644 "$SRC/catalog.xml" "$PKGDEST/usr/share/xsl-nons/docbook/catalog.xml"
	install -m 644 "$SRC/VERSION" "$PKGDEST/usr/share/xsl-nons/docbook/VERSION"
	install -m 644 "$SRC/VERSION.xsl" "$PKGDEST/usr/share/xsl-nons/docbook/VERSION.xsl"

	for directory in \
		assembly common eclipse epub epub3 fo highlighting html htmlhelp \
		images javahelp lib manpages params profiling roundtrip template \
		slides website xhtml xhtml-1_1 xhtml5; do
		install -d "$PKGDEST/usr/share/xsl-nons/docbook/$directory"
		cp -a "$SRC/$directory"/. "$PKGDEST/usr/share/xsl-nons/docbook/$directory/"
	done

	install -d "$PKGDEST/usr/share/xml/catalogs"
	install -m 644 "$RECIPE_DIR/files/docbook-xsl-nons.conf" \
		"$PKGDEST/usr/share/xml/catalogs/docbook-xsl-nons.conf"
	install -d "$PKGDEST/usr/share/licenses/$pkgname"
	install -m 644 "$SRC/COPYING" "$PKGDEST/usr/share/licenses/$pkgname/COPYING"
}

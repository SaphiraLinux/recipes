#!/bin/sh

pkgname=docbook-xsl-nons
pkgver=1.79.2
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="DocBook XSL stylesheets"
license=MIT
origin=docbook-xsl-nons
repo=main
url=https://docbook.org
source=https://github.com/docbook/xslt10-stylesheets/releases/download/release/${pkgver}/docbook-xsl-nons-${pkgver}.tar.bz2
sha256=ee8b9eca0b7a8f89075832a2da7534bce8c5478fc8fc2676f512d5d87d832102

# Offline legacy-URI coverage (2026-11-07): the shipped catalog maps
# only the cdn.docbook.org names, but consumers written against the
# historical sourceforge URIs (systemd's man pages import
# .../release/xsl/current/manpages/docbook.xsl) must resolve without
# network (xsltproc runs --nonet). The classic docbook-xsl variant maps
# those URIs natively; this variant restores parity by rewriting the
# historical prefix at this same local tree. Fail closed if upstream
# renames the anchor.

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
	# Legacy sourceforge URIs must resolve offline at this local tree
	# (see header): rewrite the historical prefix beside the shipped
	# cdn.docbook.org entries. Anchor on the shipped mapping so an
	# upstream catalog rework fails here instead of shipping a catalog
	# that silently misses - the systemd man build proved that miss
	# (xsltproc --nonet, failed external entity).
	grep -q 'cdn.docbook.org/release/xsl-nons/' \
		"$PKGDEST/usr/share/xsl-nons/docbook/catalog.xml" || {
		echo "ERROR: docbook-xsl-nons catalog anchor not found" >&2
		return 1
	}
	sed -i 's|</catalog>|  <rewriteURI uriStartString="http://docbook.sourceforge.net/release/xsl/current/" rewritePrefix="file:///usr/share/xsl-nons/docbook/"/>\n  <rewriteSystem systemIdStartString="http://docbook.sourceforge.net/release/xsl/current/" rewritePrefix="file:///usr/share/xsl-nons/docbook/"/>\n</catalog>|' \
		"$PKGDEST/usr/share/xsl-nons/docbook/catalog.xml"
	# All rewrite prefixes must be ABSOLUTE file:// URIs. The shipped
	# (and previously appended) entries used relative "./", which
	# xsltproc cannot open: libxml2 does not resolve the relative
	# result against the catalog file through delegate chains, so
	# the import fails from any working directory (proven with a
	# scratch import test: relative fails everywhere, absolute
	# succeeds). Normalize every entry, shipped or appended.
	sed -i 's|rewritePrefix="./"|rewritePrefix="file:///usr/share/xsl-nons/docbook/"|g' \
		"$PKGDEST/usr/share/xsl-nons/docbook/catalog.xml"
	grep -q 'docbook.sourceforge.net/release/xsl/current/' \
		"$PKGDEST/usr/share/xsl-nons/docbook/catalog.xml" || {
		echo "ERROR: legacy URI rewrite missing from installed catalog" >&2
		return 1
	}
	install -d "$PKGDEST/usr/share/licenses/$pkgname"
	install -m 644 "$SRC/COPYING" "$PKGDEST/usr/share/licenses/$pkgname/COPYING"
}

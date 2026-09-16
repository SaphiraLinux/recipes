#!/bin/sh

# OWASP Core Rule Set 4.25.1 LTS (data-only package, no service).
#
# LTS over latest (4.28.0): backported security/false-positive fixes
# on a stable paranoia mapping - the distro default. 4.25.1 wants
# libmodsecurity >=3.0.16 for the 901 opt-in gate (ModSecurity#3589),
# which is exactly what the libmodsecurity recipe ships.
#
# Layout: rules + plugins + utils under /usr/share/coreruleset with
# crs-setup.conf.example beside them. Engines wire it up explicitly:
# nginx includes it via modsecurity.conf (see nginx example), while
# coraza-spoa carries the same LTS line embedded and needs no path.
# No files are activated by installing this package.

pkgname=coreruleset
pkgver=4.25.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OWASP Core Rule Set 4 LTS for ModSecurity and Coraza"
license=Apache-2.0
origin=coreruleset
repo=saphira
url=https://coreruleset.org/
source=https://github.com/coreruleset/coreruleset/archive/refs/tags/v4.25.1.tar.gz
sha256=0539e66e7627fe71c160a644d8fb7ab6e450d53c9de208be5f95a35c70e1a154

depends=""
makedepends=""

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v4.25.1.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v4.25.1.tar.gz" | sha256sum -c -
	# Sanity: the LTS must contain the rule families both engines load.
	for f in crs-setup.conf.example \
		rules/REQUEST-901-INITIALIZATION.conf \
		rules/REQUEST-949-BLOCKING-EVALUATION.conf \
		rules/RESPONSE-980-CORRELATION.conf; do
		test -f "$SRC/$f" ||
			{ echo "ERROR: CRS tree missing $f" >&2; return 1; }
	done
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/share/coreruleset"
	cp -a "$SRC/crs-setup.conf.example" "$PKGDEST/usr/share/coreruleset/"
	cp -a "$SRC/rules" "$SRC/plugins" "$SRC/util" "$PKGDEST/usr/share/coreruleset/"
	cp -a "$SRC/LICENSE" "$PKGDEST/usr/share/coreruleset/"
	# No build, no tests to run: provenance is the vendored bytes
	# plus the engine-side loads (nginx modsecurity, coraza-spoa
	# validate). Keep the payload to what engines consume.
	test -f "$PKGDEST/usr/share/coreruleset/rules/REQUEST-901-INITIALIZATION.conf" ||
		{ echo "ERROR: rules missing from payload" >&2; return 1; }
}

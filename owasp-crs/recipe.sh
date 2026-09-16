#!/bin/sh

# OWASP Core Rule Set 4.29.0 (data-only package, no service).
#
# Current stable over the old LTS line: 4.29.0 carries the rule
# coverage both engines load (ModSecurity via modsecurity +
# nginx-mod-modsecurity, Coraza via coraza-spoa). CRS is
# engine-independent and explicitly supports both.
#
# Upstream is coreruleset/coreruleset (the SpiderLabs
# owasp-modsecurity-crs repository is archived and must not be
# used). No release asset ships the full tree (only -minimal plus
# signatures), so like before this pins the annotated-tag git
# archive; the vendored bytes plus sha256 are the provenance.
#
# Layout: rules + plugins + util under /usr/share/owasp-crs with
# crs-setup.conf.example beside them. The path is deliberately NEW:
# the retired coreruleset 4.25.1 LTS package owns
# /usr/share/coreruleset in the published generations, and a second
# claimant on those paths would collide at the gate. Engines wire
# this path up explicitly (see saphira-nginx-waf); nothing here is
# activated by installing the package.

pkgname=owasp-crs
pkgver=4.29.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OWASP Core Rule Set 4 for ModSecurity and Coraza"
license=Apache-2.0
origin=owasp-crs
repo=saphira
url=https://coreruleset.org/
source=https://github.com/coreruleset/coreruleset/archive/refs/tags/v4.29.0.tar.gz
sha256=cedd55533de917b6e397352a67a31993da4c07816f1fefcc94eacf542fc86337

depends=""
makedepends=""

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v4.29.0.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v4.29.0.tar.gz" | sha256sum -c -
	# Sanity: the tree must contain the rule families both engines load.
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
	mkdir -p "$PKGDEST/usr/share/owasp-crs"
	cp -a "$SRC/crs-setup.conf.example" "$PKGDEST/usr/share/owasp-crs/"
	cp -a "$SRC/rules" "$SRC/plugins" "$SRC/util" "$PKGDEST/usr/share/owasp-crs/"
	cp -a "$SRC/LICENSE" "$PKGDEST/usr/share/owasp-crs/"
	# No build, no tests to run: provenance is the vendored bytes
	# plus the engine-side loads (nginx modsecurity, coraza-spoa
	# validate). Keep the payload to what engines consume.
	test -f "$PKGDEST/usr/share/owasp-crs/rules/REQUEST-901-INITIALIZATION.conf" ||
		{ echo "ERROR: rules missing from payload" >&2; return 1; }
}

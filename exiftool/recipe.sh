#!/bin/sh

pkgname=exiftool
pkgver=13.59
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ExifTool metadata reader/writer (Perl application)"
license='Artistic-1.0-Perl OR GPL-1.0-or-later'
origin=exiftool
repo=saphira
# Licence evidence: upstream ships no standalone licence file (terms
# are "same terms as Perl itself" in README plus per-file copyright
# headers, all installed with the lib tree). Nothing further to stage;
# a fabricated LICENCE file would be worse than none.repo=saphira
url=https://exiftool.org/
source=https://download.sourceforge.net/project/exiftool/Image-ExifTool-13.59.tar.gz
sha256=668ea3acececb7235fbd0f4900e72d5f12c9b07e5c778fd36cb1e9b5828fd65a

depends="perl"

makedepends="perl"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/Image-ExifTool-13.59.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/Image-ExifTool-13.59.tar.gz" | sha256sum -c -
	# No compilation: pure-Perl application. Build phase only
	# unpacks and verifies so install() stages, never fetches.
	test -f "$SRC/exiftool" || {
		echo "ERROR: unpacked tree is missing the exiftool script" >&2
		return 1
	}
	test -d "$SRC/lib" || {
		echo "ERROR: unpacked tree is missing lib/" >&2
		return 1
	}
}

recipe_install()
{
	# site_perl resolved from the target perl, never hardcoded: the
	# path carries the interpreter version.
	site=$(perl -MConfig -e 'print $Config{installsitelib}')
	[ -n "$site" ] || {
		echo "ERROR: cannot resolve perl installsitelib" >&2
		return 1
	}
	install -D -m 0755 "$SRC/exiftool" "$PKGDEST/usr/bin/exiftool"
	mkdir -p "$PKGDEST$site"
	cp -a "$SRC/lib/." "$PKGDEST$site/" || {
		echo "ERROR: cannot stage ExifTool library tree" >&2
		return 1
	}
	# The application must actually be staged.
	test -f "$PKGDEST$site/Image/ExifTool.pm" || {
		echo "ERROR: staged payload is missing Image/ExifTool.pm" >&2
		return 1
	}
}

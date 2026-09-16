#!/bin/sh

pkgname=perl
pkgver=5.44.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Practical Extraction and Report Language'
license='Artistic-1.0-Perl OR GPL-1.0-or-later'
origin=perl
repo=saphira
url=https://www.perl.org/
source=https://cpan.metacpan.org/authors/id/L/LE/LEONT/perl-${pkgver}.tar.gz
sha256=3b855066b92491cb40e86affb1ca57d1a388aa43e51b91c7806a32c2f65f96c3

depends=""

makedepends="
	gcc
	make
"

# Modern perl: current stable, threads + shared libperl (dynamic
# consumers link the .so - no static-archive PIC workarounds needed).
# Per-platform Configure defaults already supply _GNU_SOURCE, large
# files and friends on linux; only uselargefiles is stated explicitly.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/perl-${pkgver}.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/perl-${pkgver}.tar.gz"

	cd "$SRC"

	./Configure -des \
		-Dprefix=/usr \
		-Dscriptdir=/usr/bin \
		-Dman1dir=/usr/share/man/man1 \
		-Dman3dir=/usr/share/man/man3 \
		-Dman1ext=1 \
		-Dman3ext=3pm \
		-Dusethreads \
		-Duseshrplib

	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install

	find "$PKGDEST" -name perllocal.pod -delete
	# Section-0 sweep: 5.44.0-r1 shipped 965 sectionless .0 files (vs
	# three strays in 5.42.0-r1) after the man dirs went implicit - one
	# dangling alias among them (perlthanks.0 -> ./perlbug.0) made the
	# APK uninstallable, and man(1) displays no section 0 anyway.
	# Explicit dirs+exts above are the fix; the sweep handles strays
	# the way perllocal.pod is handled. The real sections must survive
	# it, or the build fails here instead of shipping doc-less perl.
	find "$PKGDEST/usr/share/man" -name '*.0' -delete
	test -f "$PKGDEST/usr/share/man/man1/perl.1"
	test -n "$(find "$PKGDEST/usr/share/man/man3" -name '*.3pm' -print -quit)"
	test -z "$(find "$PKGDEST/usr/share/man" -name '*.0' -print -quit)"

	test -x "$PKGDEST/usr/bin/perl"
	find "$PKGDEST/usr/lib" -name 'libperl.so*' -type f | grep -q .
}

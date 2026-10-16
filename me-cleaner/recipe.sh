#!/bin/sh
pkgname=me-cleaner
pkgver=1.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Intel ME/TXE firmware partial-deblobbing tool (modifies images, x86 firmware scope)'
license='GPL-3.0-or-later'
origin=me-cleaner
repo=saphira
url=https://github.com/corna/me_cleaner
# Canonical upstream only (corna/me_cleaner tag v1.2). No fork is
# substituted under this name; newer-fork support claims are recorded
# separately for later review, not shipped here.
source=https://github.com/corna/me_cleaner/archive/refs/tags/v${pkgver}.tar.gz
sha256=ca9a8a7bef6737f5e039d2bb5c05c3ba71e7cd8f530ef393a12683a88257b641

# Pure-Python tool. Upstream shebang says /usr/bin/python; Saphira ships
# python3, so the installed script is re-pointed at /usr/bin/python3.
# README.md ships in doc/: it carries the upstream generation-support
# limits (gen1 full removal, gen2 near-full, gen3/Skylake+ partial) and
# must be read before use — this tool is NOT a universal ME disabler.
depends="python3"
makedepends=""

recipe_build() {
	# Tag tarball vendored under URL basename (libconfuse precedent).
	ME_BALL="$RECIPE_DIR/files/v${pkgver}.tar.gz"
	echo "$sha256  $ME_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$ME_BALL"
	python3 -m py_compile "$SRC/me_cleaner.py"
}

recipe_install() {
	mkdir -p "$BUILDDIR"
	sed 's|^#!/usr/bin/python$|#!/usr/bin/python3|' \
		"$SRC/me_cleaner.py" > "$BUILDDIR/me_cleaner.py"
	install -D -m 0755 "$BUILDDIR/me_cleaner.py" \
		"$PKGDEST/usr/bin/me_cleaner.py"
	install -D -m 0644 "$SRC/man/me_cleaner.1" \
		"$PKGDEST/usr/share/man/man1/me_cleaner.1"
	install -D -m 0644 "$SRC/README.md" \
		"$PKGDEST/usr/share/doc/me-cleaner/README.md"
}

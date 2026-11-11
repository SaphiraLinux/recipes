#!/bin/sh

pkgname=fasm
pkgver=1.73.35
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Flat assembler for x86 and x86-64 (self-hosting, static binary)'
license='BSD-2-Clause'
origin=fasm
repo=saphira
url=https://flatassembler.net/
vendor=https://flatassembler.net/fasm-1.73.35.tgz
sha256=a34dec7d0bc2dc79faabb68bd8bc2f62b6cfb31d69c01449367ce4cd8098934e

# 1.73.35: current upstream (24 Feb 2026). fasm 2/fasmg is a separate
# engine with different syntax and is not this package.
#
# Self-hosting bootstrap, all inside the one vendored archive: fasm
# sources are assembly and assemble only with fasm itself, so the
# included 1.73.35 x64 binary assembles the included 1.73.35 sources.
# No external seed, no network, no compiler - makedepends stays empty
# (37 precedents tree-wide). The stage1==stage2 identity proof below
# is what makes the seed trustworthy: a seed that smuggled anything
# in would have to reproduce itself exactly through the fresh binary.
#
# License is the license.txt BSD-2-Clause grant ("free for commercial
# and non-commercial use"); its condition 2 requires the notice to
# travel with binary distributions, so license.txt ships in main next
# to the binary, not only in -doc. Upstream ships no man page
# (Debian builds none either); the binary documents itself.
#
# Only the x86-64 Linux port is built (SAPHIRA_ARCH is x86_64): the
# 32-bit fasm in the archive is x86-only payload Saphira cannot run
# without a compat layer it does not ship.

depends=""
makedepends=""

subpackages="$pkgname-doc"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/fasm-1.73.35.tgz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/fasm-1.73.35.tgz"

	seed=$SRC/fasm.x64
	test -x "$seed" || {
		echo "ERROR: seed assembler missing: $seed" >&2
		return 1
	}
	# Includes resolve relative to the source tree (modes.inc beside
	# fasm.asm, ../../*.inc up in source/), so assemble from the
	# x64 directory itself.
	cd "$SRC/source/linux/x64" || return 1
	"$seed" fasm.asm "$BUILDDIR/fasm-stage1" || {
		echo "ERROR: seed assembly failed" >&2
		return 1
	}
	test -x "$BUILDDIR/fasm-stage1" || {
		echo "ERROR: stage1 binary missing" >&2
		return 1
	}
	"$BUILDDIR/fasm-stage1" fasm.asm "$BUILDDIR/fasm-stage2" || {
		echo "ERROR: self-assembly failed" >&2
		return 1
	}
	if ! cmp -s "$BUILDDIR/fasm-stage1" "$BUILDDIR/fasm-stage2"; then
		echo "ERROR: stage1 and stage2 differ (seed not self-consistent)" >&2
		return 1
	fi
	# Functional smoke test with upstream's own self-contained
	# example: the shipped binary must assemble working x86-64 ELF.
	"$BUILDDIR/fasm-stage2" \
		"$SRC/examples/elfexe/hello64.asm" "$BUILDDIR/hello64" || {
		echo "ERROR: smoke assembly failed" >&2
		return 1
	}
	test -s "$BUILDDIR/hello64" || {
		echo "ERROR: smoke assembly produced no output" >&2
		return 1
	}
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/fasm-stage2" "$PKGDEST/usr/bin/fasm"
	install -D -m 0644 "$SRC/license.txt" \
		"$PKGDEST/usr/share/licenses/$pkgname/license.txt"
	install -D -m 0644 "$SRC/fasm.txt" \
		"$PKGDEST/usr/share/doc/$pkgname/fasm.txt"
	install -D -m 0644 "$SRC/whatsnew.txt" \
		"$PKGDEST/usr/share/doc/$pkgname/whatsnew.txt"
	test -x "$PKGDEST/usr/bin/fasm" || {
		echo "ERROR: packaged fasm missing: $PKGDEST/usr/bin/fasm" >&2
		return 1
	}
	test -s "$PKGDEST/usr/share/doc/$pkgname/fasm.txt" || {
		echo "ERROR: packaged manual missing" >&2
		return 1
	}
}

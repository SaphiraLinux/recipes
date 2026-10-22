#!/bin/sh

pkgname=bonnie
pkgver=1.04
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Bonnie++ filesystem benchmark (bonnie++, zcav, converters)'
license='GPL-2.0-or-later'
origin=bonnie
repo=saphira
url=https://www.coker.com.au/bonnie++/
source=https://www.coker.com.au/bonnie++/bonnie++_1.04.tgz
sha256=507bd2ce5360c7c98b91b0fdc2bed5c9320b5c9699f7d4a3d1c86b256896c15e
# r1: initial native port. Upstream's own download page is the authority
# (1.04 is current there); the hash is trust-on-first-use, recorded
# 2026-10-22, vendored bytes are the source of truth afterwards.
# Upstream's Makefile has no DESTDIR support, so installation is by
# explicit file list (a missing binary fails the build instead of
# shipping short). The CSV converters are perl scripts, hence the
# perl runtime dependency. The C++ runtime comes from gcc-libs: the
# builder's RUNTIME linkage gate installs into a minimal root where
# libstdc++.so.6/libgcc_s.so.1 are otherwise unresolvable (proven by
# the gate failing without it).

depends="gcc-libs perl"
makedepends="gcc make"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/bonnie++_1.04.tgz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/bonnie++_1.04.tgz"
	cd "$SRC"
	./configure --prefix=/usr
	make -j"$(nproc)"
	# Proof: the binaries exist and answer. bonnie++ -h prints
	# usage without touching a disk.
	[ -x ./bonnie++ ] ||
		{ echo "ERROR: bonnie++ binary missing" >&2; return 1; }
	./bonnie++ -h >"$BUILDDIR/usage.txt" 2>&1 || true
	grep -qi usage "$BUILDDIR/usage.txt" ||
		{ echo "ERROR: bonnie++ proof failed" >&2; return 1; }
}

recipe_install()
{
	cd "$SRC"
	for b in "bonnie++" zcav; do
		[ -x "$b" ] || { echo "ERROR: $b missing at install" >&2; return 1; }
		install -D -m 0755 "$b" "$PKGDEST/usr/sbin/$b"
	done
	for s in bon_csv2html bon_csv2txt; do
		[ -f "$s" ] || { echo "ERROR: $s missing at install" >&2; return 1; }
		install -D -m 0755 "$s" "$PKGDEST/usr/bin/$s"
	done
	for m in *.1; do
		[ -f "$m" ] || continue
		install -D -m 0644 "$m" "$PKGDEST/usr/share/man/man1/$m"
	done
	for m in *.8; do
		[ -f "$m" ] || continue
		install -D -m 0644 "$m" "$PKGDEST/usr/share/man/man8/$m"
	done
}

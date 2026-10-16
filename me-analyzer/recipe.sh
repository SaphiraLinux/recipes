#!/bin/sh
pkgname=me-analyzer
pkgver=1.312.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Intel ME/CSME/TXE/SPS/GSC firmware inspection tool (read-only analysis)'
license='BSD-2-Clause-Patent'
origin=me-analyzer
repo=saphira
url=https://github.com/platomav/MEAnalyzer
# Pinned tag v1.312.0-r378 (DB r378). Databases ship with the package;
# analysis never downloads anything. The background new-version notice
# is best-effort and exception-swallowed offline; pass -duc to silence
# it entirely on air-gapped machines.
source=https://github.com/platomav/MEAnalyzer/archive/refs/tags/v1.312.0-r378.tar.gz
sha256=59512f4b2175a75c0db0e8a86787d9384d09e8842cb3ee5afed49c7a251dc75b

depends="python3 python-colorama python-crccheck python-pltable"
makedepends=""

recipe_build() {
	MEA_BALL="$RECIPE_DIR/files/v1.312.0-r378.tar.gz"
	echo "$sha256  $MEA_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$MEA_BALL"
	python3 -m py_compile "$SRC/MEA.py"
	for db in MEA.dat Huffman.dat FileTable.dat; do
		[ -f "$SRC/$db" ] || { echo "me-analyzer: missing database $db" >&2; return 1; }
	done
}

recipe_install() {
	mkdir -p "$BUILDDIR"
	for f in MEA.py MEA.dat Huffman.dat FileTable.dat LICENSE README.md Changelog.txt; do
		install -D -m 0644 "$SRC/$f" "$PKGDEST/usr/share/me-analyzer/$f"
	done
	chmod 0755 "$PKGDEST/usr/share/me-analyzer/MEA.py"
	# mea_dir follows symlinks (realpath), so the databases resolve
	# next to the real script through this link.
	mkdir -p "$PKGDEST/usr/bin"
	ln -sf ../share/me-analyzer/MEA.py "$PKGDEST/usr/bin/meanalyzer"
}

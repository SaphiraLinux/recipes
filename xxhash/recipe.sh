#!/bin/sh

pkgname=xxhash
pkgver=0.8.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Extremely fast non-cryptographic hash algorithm (XXH3, XXH64, XXH32)"
license="BSD-2-Clause"
origin=xxhash
repo=saphira
url=https://xxhash.com/
source=https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.3.tar.gz
sha256=aae608dfe8213dfd05d909a57718ef82f30722c392344583d3f39050c7f29a80

subpackages="$pkgname-dev $pkgname-doc"
makedepends="
    binutils
    gcc
    make
"

# Full default build: CLI tools (xxhsum) and shared + static libraries.
# Development files ship in the main package; no -dev split.
recipe_build()
{
	make -C "$SRC"
}

recipe_install()
{
	make -C "$SRC" PREFIX=/usr DESTDIR="$PKGDEST" install
}

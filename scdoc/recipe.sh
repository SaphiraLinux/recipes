#!/bin/sh

pkgname=scdoc
pkgver=1.11.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Small man-page generator for scdoc syntax (rpm build tooling)'
license='MIT'
origin=scdoc
repo=saphira
url=https://sr.ht/~sircmpwn/scdoc/
source=https://git.sr.ht/~sircmpwn/scdoc/archive/1.11.4.tar.gz
sha256=e1a9c2000f855123a1a50c8f897073e0ee95fc41787431efe3864c2f1c2e7092
# Provenance: sr.ht publishes no hashes for this artifact. Hash
# recorded from the TLS-verified upstream download and verified by
# clean extraction; it pins the vendored bytes for every future
# fetch.
depends=""
makedepends="gcc make"
subpackages="$pkgname-doc"

recipe_build()
{
	make -C "$SRC" -j${JOBS:-$(nproc)} PREFIX=/usr
}

recipe_install()
{
	make -C "$SRC" PREFIX=/usr DESTDIR="$PKGDEST" install
}

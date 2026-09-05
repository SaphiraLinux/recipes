#!/bin/sh

pkgname=rust-src
pkgver=1.97.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Rust standard library source (rust-analyzer type info, -Zbuild-std)"
license="MIT OR Apache-2.0"
origin=rust-src
repo=main
url=https://www.rust-lang.org/
# Same official dist source tarball as rustc; only the std sources are shipped.
source=https://static.rust-lang.org/dist/rustc-1.97.1-src.tar.xz
sha256=0ed06fdaffd4722a7702e0b4eebfafc897ab8f513e8e1b247cdd7e5c6df6ded2

recipe_build()
{
	# No build: payload is the std library source tree from the dist tarball.
	test -d "$SRC/library"
}

recipe_install()
{
	install -d "$PKGDEST/usr/lib/rustlib/src/rust" \
		"$PKGDEST/usr/share/licenses/rust-src"
	cp -a "$SRC/library" \
		"$PKGDEST/usr/lib/rustlib/src/rust/library"
	install -m 0644 "$SRC/LICENSE-APACHE" \
		"$PKGDEST/usr/share/licenses/rust-src/LICENSE-APACHE"
	install -m 0644 "$SRC/LICENSE-MIT" \
		"$PKGDEST/usr/share/licenses/rust-src/LICENSE-MIT"
}

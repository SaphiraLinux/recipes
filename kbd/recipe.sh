#!/bin/sh

pkgname=kbd
pkgver=2.10.0
pkgrel=2
# r2: depends gains gzip. kbd's keymap/font console tools read the
# shipped .map.gz/.psf.gz payloads through libkbdfile, which was built
# here without zlib support, so its only .gz path is popen("gzip -d -c").
# Without gzip every OpenRC boot logs "sh: line 1: gzip: command not
# found" at "Loading key mappings" (proven on a 0.2.1 guest: loadkeys
# carries no libz reference, only the "gzip -d -c" fallback string).
# gzip is therefore a genuine runtime dependency, not a suppressible
# warning.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Linux console keyboard tools (loadkeys, kbd_mode, dumpkeys)'
license='GPL-2.0-or-later'
origin=kbd
repo=saphira
url=https://www.kernel.org/pub/linux/utils/kbd/
# Vendored: https://www.kernel.org/pub/linux/utils/kbd/kbd-2.10.0.tar.xz
# (sha256 cross-checked against upstream sha256sums.asc; no gpg keyring
# in the build root to check the .sign against - same bar as the tree's
# other vendored upstreams).
kbd_sha256=6e5ca4f8d76ee9e3a8db700b667f13e12aac9933828a64e1aaad93d26be9b479

# No runtime deps beyond libc and the decompressor the tools shell
# out to: the tools are self-contained C, but compressed console data
# goes through "gzip -d -c" (see r2).
# --disable-vlock keeps PAM out of the base console tools; --disable-xkb
# keeps libxkbcommon out (kernel keymaps only); tests and NLS follow
# the tree baseline (off).
depends="musl gzip"
makedepends="bison flex gcc make pkgconf"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/kbd-2.10.0.tar.xz"
	cd "$SRC"
	echo "$kbd_sha256  $RECIPE_DIR/files/kbd-2.10.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-nls --disable-vlock --disable-tests --disable-xkb
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

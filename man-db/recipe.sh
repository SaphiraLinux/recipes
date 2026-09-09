#!/bin/sh
pkgname=man-db
pkgver=2.13.0
# r5: musl //IGNORE fallback (manconv requests UTF-8//IGNORE on its
# last encoding guess; musl rejects the suffix with EINVAL, so a page
# with undeterminable encoding errored instead of converting -
# proven live via iconv_open EINVAL probe). NOTE: first mechanized
# build (fragment now generates scripts): remove any historical
# manual man entry with a different UID (e.g. local 999 bodge)
# BEFORE installing r5 - same-name/different-UID is fatal.
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Database-driven manual pager suite (man, apropos, whatis)'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=man-db
repo=saphira
url=https://www.nongnu.org/man-db/
man_db_sha256=82f0739f4f61aab5eb937d234de3b014e777b5538a28cbd31433c45ae09aefb9
depends="libpipeline gdbm zlib groff"
makedepends="libpipeline-dev gdbm-dev zlib-dev gettext gcc make pkgconf"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/man-db-2.13.0.tar.xz"
	echo "$man_db_sha256  $RECIPE_DIR/files/man-db-2.13.0.tar.xz" | sha256sum -c -
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/musl-iconv-fallback.patch"
	cd "$SRC"
	echo "$man_db_sha256  $RECIPE_DIR/files/man-db-2.13.0.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc \
		--disable-nls --disable-static \
		--with-db=gdbm --with-pager=less \
		--disable-setuid --enable-automatic-create
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Runtime identity declaration: upstream configures MAN_OWNER=man
	# (system-wide cache files owned by man) while accounts.tsv carries
	# only the man group. makepkg generates the install scripts from
	# this fragment; the package creates its user at install time.
	# r4: fragment added (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/man-db" \
		"$PKGDEST/usr/share/saphira/accounts.d/man-db"
}

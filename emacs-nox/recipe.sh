pkgname=emacs-nox
pkgver=30.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU Emacs terminal (non-X) build'
license='GPL-3.0-or-later'
origin=emacs-nox
repo=saphira
url=https://www.gnu.org/software/emacs/
source=https://ftp.gnu.org/gnu/emacs/emacs-${pkgver}.tar.xz
sha256=b3f36f18a6dd2715713370166257de2fae01f9d38cfe878ced9b1e6ded5befd9

depends="ncurses glib gmp libxml2 acl"
# No kernel UAPI consumption in this configuration: --without-file-notification
# (no inotify), no libseccomp (seccomp-filter helper not built), Android port
# not built. The only linux/ includes upstream are those three paths.
makedepends="gcc make pkgconf gawk texinfo glib-dev gmp-dev libxml2-dev acl-dev ncurses-dev"

recipe_build() {
	# Lean terminal build: no X, no sound, no file notifications (inotify
	# via kernel headers is available but glib/gio notifications are
	# pulled separately), no tree-sitter (not in the tree), no lcms2.
	./configure --prefix=/usr --without-x --without-sound \
		--without-file-notification --without-tree-sitter \
		--without-javascript --with-gameuser=root \
		--with-gnutls=ifavailable \
		MAKEINFO=/bin/true
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
	# game score helper must not be suid in a rootless-built package
	chmod 0755 "$PKGDEST/usr/lib/emacs/$pkgver/x86_64-akadata-linux-musl/update-game-score" 2>/dev/null || true
}

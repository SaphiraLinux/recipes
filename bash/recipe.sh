#!/bin/sh
pkgname=bash
pkgver=5.3
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU Bourne-Again shell - Saphira /bin/sh'
license='GPL-3.0-or-later'
origin=bash
repo=saphira
url=https://www.gnu.org/software/bash/
bash_sha256=0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba
depends="ncurses"
makedepends="gawk gcc make ncurses-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/bash-5.3.tar.gz"
	cd "$SRC"
	echo "$bash_sha256  $RECIPE_DIR/files/bash-5.3.tar.gz" | sha256sum -c -
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--bindir=/bin \
		--without-bash-malloc \
		--disable-nls \
		bash_cv_getcwd_malloc=yes
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Saphira /bin/sh is a relative link to bash owned by this package:
	# the target lives here, so the link lives here too. Every makepkg-
	# generated maintainer script uses a #!/bin/sh shebang, and a clean
	# apk --root install runs those scripts with only dependencies
	# installed first -- so without this link the first script fails
	# execve 127. Controller fallbacks (buildpkg root-init,
	# saphira-bootstrap, initialise_install_root) tolerate a pre-existing
	# correct link and only create it when absent.
	ln -s bash "$PKGDEST/bin/sh"
}

#!/bin/sh
pkgname=doxygen-awesome-css
pkgver=2.4.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Doxygen awesome theme assets (CSS/JS for libssh API docs, no build)'
license='MIT'
origin=doxygen-awesome-css
repo=saphira
url=https://github.com/jothepro/doxygen-awesome-css
source=https://github.com/jothepro/doxygen-awesome-css/archive/refs/tags/v2.4.1.tar.gz
sha256=da313e9ed72260c0c0690e8c93f409dc426183dae6d7772d30cad8875b2e11b3

# Data-only theme assets. libssh passes this directory as
# -DDOXYGEN_AWESOME_CSS_DIR so its docs build never downloads the
# theme at build time (upstream default fetches a tarball).
depends=""
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/share/doxygen-awesome-css"
	cp -a "$SRC"/doxygen-awesome.css "$SRC"/doxygen-awesome-*.js "$PKGDEST/usr/share/doxygen-awesome-css/"
}

#!/bin/sh

pkgname=git
pkgver=2.55.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Distributed version control system'
license='GPL-2.0-or-later'
origin=git
repo=saphira
url=https://git-scm.com/
source=https://www.kernel.org/pub/software/scm/git/git-${pkgver}.tar.xz
sha256=457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357

depends="curl expat openssl zlib pcre2 perl"
makedepends="gcc make pkgconf perl gettext curl-dev expat-dev openssl-dev zlib-dev pcre2-dev"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --with-perl=/usr/bin/perl \
		--with-curl --with-expat --with-openssl --with-zlib
	make -j${JOBS:-$(nproc)} NO_TCLTK=YesPlease \
		NO_RUST=YesPlease USE_LIBPCRE2=YesPlease \
		INSTALL_SYMLINKS=YesPlease all
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" prefix=/usr NO_TCLTK=YesPlease \
		NO_RUST=YesPlease USE_LIBPCRE2=YesPlease \
		INSTALL_SYMLINKS=YesPlease install
	for command in git-archimport git-cvsexportcommit git-cvsimport \
		git-cvsserver git-p4 git-svn; do
		rm -f "$PKGDEST/usr/libexec/git-core/$command"
	done
}

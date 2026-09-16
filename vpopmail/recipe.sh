#!/bin/sh

pkgname=vpopmail
pkgver=5.6.13
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="virtual domain/user manager for qmail (Toaster account machinery, MySQL backend)"
# In-tree LICENSE is the GPLv3 text while file headers carry the
# classic v2-or-later clause; record the conjunction, not one side.
license="GPL-2.0-or-later AND GPL-3.0-only"
origin=vpopmail
repo=main
url=https://github.com/sagredo-dev/vpopmail
subpackages="
    $pkgname-dev
"
# Pinned commit of the sagredo-dev/vpopmail main branch (the actively
# maintained tree qmail's chkuser builds against); full SHA in
# source=, snapshot date in the comment. HEAD 2026-09: 8f77b5d
# ("backfill.c: fix const qualifier warnings in strrstr()").
source=https://github.com/sagredo-dev/vpopmail/archive/8f77b5d00cd0f75417e3071848a9276cb3ad53f3.tar.gz
sha256=f51ce471a9d4f0620106d44ab7317b54a27c8b2b602e062ce6fd8902f103d33e

depends="
    libxcrypt
    mariadb
    zlib
"

makedepends="
    autoconf
    automake
    binutils
    gawk
    gcc
    libxcrypt-dev
    make
    mariadb-dev
    pkgconf
    zlib-dev
"

recipe_build()
{
	# Rootless-staging patch (see files/saphira-rootless.patch):
	# getpwnam probe falls back to SAPHIRA_VPOPMAIL_* pre-seeds
	# (fixed UID 140 / GID 141), host /home/vpopmail creation is
	# skipped, and install ownership flags become no-ops (the
	# accounts.d file/dir stanzas apply ownership at install).
	# Regenerated with the tree autoconf/automake (2.71/1.18-era
	# sources); if regeneration ever breaks, hand-patch the
	# generated configure/Makefile.in identically instead.
	patch -p1 < "$RECIPE_DIR/files/saphira-rootless.patch"
	autoreconf -fi
	export SAPHIRA_VPOPMAIL_DIR=/home/vpopmail \
		SAPHIRA_VPOPMAIL_UID=140 \
		SAPHIRA_VPOPMAIL_GID=141 \
		SAPHIRA_NO_HOST_DIRS=1
	# Toaster-shaped backend: MySQL auth with many-domains (one SQL
	# table for all domains), qmail paths passed explicitly so no
	# qmail presence is needed at vpopmail build time (vpopmail
	# builds before qmail here - the reverse of the classic order -
	# because qmail's chkuser compiles against vpopmail headers).
	# K&R-era codebase under gcc 16 (default gnu23): empty-paren
	# declarations mean zero params in C23, breaking old call sites
	# (vpalias valias_select_next). -std=gnu17 restores unspecified
	# args (m4/make/groff precedent; qmail itself builds on gnu17).
	export CFLAGS="${CFLAGS-} -std=gnu17"
	./configure 		--prefix=/usr 		--sysconfdir=/etc 		--localstatedir=/var 		--disable-static 		--enable-auth-module=mysql 		--enable-incdir=/usr/include/mysql 		--enable-libdir=/usr/lib 		--enable-qmaildir=/var/qmail 		--enable-vpopuser=vpopmail 		--enable-vpopgroup=vchkpw 		--enable-many-domains 		--enable-non-root-build 		--enable-qmail-newu=/var/qmail/bin/qmail-newu 		--enable-qmail-inject=/var/qmail/bin/qmail-inject 		--enable-qmail-newmrh=/var/qmail/bin/qmail-newmrh
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# -dev placement: upstream installs the static lib and the public
	# header set under /home/vpopmail; relocate to /usr so the
	# automatic -dev split carries them (runtime paths stay
	# upstream-verbatim). The relocated set is exactly what
	# Makefile.am installs for third-party builds (qmail chkuser,
	# qmailadmin).
	mkdir -p "$PKGDEST/usr/lib" "$PKGDEST/usr/include/vpopmail"
	mv "$PKGDEST/home/vpopmail/lib/libvpopmail.a" "$PKGDEST/usr/lib/"
	mv "$PKGDEST/home/vpopmail/include/"* "$PKGDEST/usr/include/vpopmail/"
	rmdir "$PKGDEST/home/vpopmail/include" "$PKGDEST/home/vpopmail/lib"
	# Third-party builds read these flag files; point them at the
	# relocated -dev paths (prefix rewrite preserves the configured
	# auth libs verbatim).
	sed -i 's|-I/home/vpopmail/include|-I/usr/include/vpopmail|' \
		"$PKGDEST/home/vpopmail/etc/inc_deps"
	sed -i 's|-L/home/vpopmail/lib|-L/usr/lib|' \
		"$PKGDEST/home/vpopmail/etc/lib_deps"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/vpopmail" \
		"$PKGDEST/usr/share/saphira/accounts.d/vpopmail"
	# vpopmaild service units deferred: the daemon's runtime shape
	# (foreground mode, config surface) gets its own review with the
	# SMTP-listener phase, not smuggled into r1.
}

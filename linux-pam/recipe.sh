#!/bin/sh

pkgname=linux-pam
pkgver=1.7.2
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Pluggable Authentication Modules (limits, unix auth for system services)"
license="GPL-2.0-or-later"
origin=linux-pam
repo=saphira
url=https://github.com/linux-pam/linux-pam
source=https://github.com/linux-pam/linux-pam/releases/download/v1.7.2/Linux-PAM-1.7.2.tar.xz
sha256=3d86b6383fb5fd9eb9578d2cd47d92801191f4bf3f9bc61419bfefc8aa1e531a

# Makes fork-bomb class abuse limitable (pam_limits): the mechanism,
# not a policy - this package ships only the limits.d/namespace.d
# directories (examples stay off, so even upstream's commented
# examples are absent). The default policy is saphira-pambase's
# limits.d/10-saphira.conf; services opt into modules via their own
# /etc/pam.d entries; no auto-enablement here.
# No daemon, no service identities.
depends="
    gettext
    libxcrypt
"

makedepends="
    binutils
    bison
    flex
    gcc
    gettext-dev
    libxcrypt-dev
    make
    meson
    ninja
    pkgconf
"

# Feature states (meson feature options; auto would silently follow
# whatever the worker happens to hold, so intended states are explicit):
# i18n on (gettext live); docs off (no asciidoc toolchain - costs the
# generated man pages, noted, not silent); audit/selinux/nis/econf/
# pwaccess/logind off (no audit, selinux, nis, econf, pwaccess or
# systemd-dev providers in the tree - re-enable as those land);
# openssl left at upstream default (disabled) for pam_timestamp;
# examples off (payload hygiene).
recipe_build()
{
	# Prefer libxcrypt explicitly at configure time; see the patch.
	patch -Np1 -d "$SRC" -i "$RECIPE_DIR/files/0001-saphira-require-libxcrypt.patch"
	# struct crypt_data sizing: pam_unix allocates it and calls crypt_r(),
	# so it must see libxcrypt's 32KiB definition, not musl's 260-byte one.
	# A musl-sized struct passed to libxcrypt's crypt_r overflows ~32KiB
	# into whatever follows and segfaults (proven: shadow passwd r9).
	# libxcrypt's include directory goes first, mirroring shadow.
	export CPPFLAGS="-I/usr/include/libxcrypt ${CPPFLAGS-}"
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Di18n=enabled \
		-Ddocs=disabled \
		-Daudit=disabled \
		-Deconf=disabled \
		-Dlogind=disabled \
		-Delogind=disabled \
		-Dselinux=disabled \
		-Dnis=disabled \
		-Dpwaccess=disabled \
		-Dexamples=false
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}

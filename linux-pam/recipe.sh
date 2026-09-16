#!/bin/sh

pkgname=linux-pam
pkgver=1.7.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Pluggable Authentication Modules (limits, unix auth for system services)"
license="GPL-2.0-or-later"
origin=linux-pam
repo=saphira
url=https://github.com/linux-pam/linux-pam
source=https://github.com/linux-pam/linux-pam/releases/download/v1.7.2/Linux-PAM-1.7.2.tar.xz
sha256=3d86b6383fb5fd9eb9578d2cd47d92801191f4bf3f9bc61419bfefc8aa1e531a

# Makes fork-bomb class abuse limitable (pam_limits): the mechanism,
# not a policy - this package ships upstream's commented example
# limits only and activates nothing. Services opt into specific
# modules via their own /etc/pam.d entries; no auto-enablement here.
# No daemon, no service identities.
depends="
    gettext
"

makedepends="
    binutils
    bison
    flex
    gcc
    gettext-dev
    make
    meson
    ninja
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

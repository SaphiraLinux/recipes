#!/bin/sh

pkgname=openssh
pkgver=10.3_p1
pkgrel=8
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OpenBSD Secure Shell server and client"
license="BSD-2-Clause"
origin=openssh
repo=main
url=https://www.openssh.com/
source=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.3p1.tar.gz
sha256=56682a36bb92dcf4b4f016fd8ec8e74059b79a8de25c15d670d731e7d18e45f4

# libmd is a runtime requirement on musl builds and was historically
# missing from the inherited packaging's dependency list.
depends="
    libmd
    zlib
"

makedepends="
    binutils
    gawk
    gcc
    make
    libmd-dev
    openssl-dev
    pkgconf
    zlib-dev
"

replaces="openssh-client openssh-server"
subpackages="openssh-doc"
recipe_build()
{
	# Preserve the proven Saphira v0 openssh build decisions: separate
	# libexecdir, /var/empty privilege-separation directory, pid in
	# /var/run/sshd (r8: split-/run invariant, was /run), no
	# PAM/selinux/rpath, no strip phase.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc/ssh \
		--localstatedir=/var \
		--libexecdir=/usr/lib/ssh \
		--with-privsep-user=sshd \
		--with-privsep-path=/var/empty \
		--with-pid-dir=/var/run/sshd \
		--without-pam \
		--without-selinux \
		--without-rpath \
		--disable-strip
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install-nokeys
	install -D -m 0755 "$SRC/contrib/ssh-copy-id" \
		"$PKGDEST/usr/bin/ssh-copy-id"
	install -d -m 0755 "$PKGDEST/etc/ssh" "$PKGDEST/var/empty"
	install -m 0644 "$RECIPE_DIR/files/sshd_config" \
		"$PKGDEST/etc/ssh/sshd_config"
	install -d -m 0755 "$PKGDEST/etc/init.d" "$PKGDEST/usr/lib/systemd/system"
	install -m 0755 "$RECIPE_DIR/files/sshd.initd" \
		"$PKGDEST/etc/init.d/sshd"
	install -m 0644 "$RECIPE_DIR/files/sshd.service" \
		"$PKGDEST/usr/lib/systemd/system/sshd.service"
	find "$PKGDEST/etc/ssh" -type f -name 'ssh_host_*' -delete
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# sshd starts as root, so the runtime dir is root-owned; makepkg
	# runs ensure-fhs on install/upgrade (no accounts.d ordering need
	# beyond the privsep identity, which is unchanged).
	# r8: pid dir /run -> /var/run/sshd (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/openssh" \
		"$PKGDEST/usr/share/saphira/fhs.d/openssh"
	# Runtime identity declaration: sshd:101 required by privilege
	# separation. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	# r7: fragment added (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/openssh" \
		"$PKGDEST/usr/share/saphira/accounts.d/openssh"
}

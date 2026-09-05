#!/bin/sh

pkgname=openssh
pkgver=10.3_p1
pkgrel=6
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
	# libexecdir, /var/empty privilege-separation directory, pid in /run,
	# no PAM/selinux/rpath, no strip phase.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc/ssh \
		--libexecdir=/usr/lib/ssh \
		--with-privsep-user=sshd \
		--with-privsep-path=/var/empty \
		--with-pid-dir=/run \
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
}

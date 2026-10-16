#!/bin/sh

pkgname=openssh
pkgver=10.5_p1
pkgrel=5
# r5: sshd OpenRC first-start host-key generation (ssh-keygen -A in
# start_pre before sshd -t; idempotent, never replaces keys), matching
# the systemd unit's ExecStartPre semantics. Without it sshd cannot
# start on a fresh OpenRC system (remote-access blocking, boot
# unaffected). Proven by openssh/tests/sshd-hostkeys.sh (fails on the
# old initd with 'no hostkeys available', passes with 4 key types and
# stable hashes on the new one).
# r2: sshd service joins the shared stacks (include system-remote-login
# from saphira-pambase) instead of a private 4-stack pam_unix.
# Payload change, revision bumps.
# r3: merge line (r8 /var/run/sshd pid-dir + fhs.d migration adopted
# from hotfix/var-packaging-bug-var-run-isnot-run so this lineage
# never regresses it; hatched publishes 10.5_p1 only through r2 and
# 10.5_p1-r3 was never published, so r3 is the next revision).
# Payload change, bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OpenBSD Secure Shell server and client"
license="BSD-2-Clause"
origin=openssh
repo=main
url=https://www.openssh.com/
source=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.5p1.tar.gz
sha256=d44d28a839ea9daf969cc69150fde59910b2b39361dad81a3bd6cbd19218db11

# libmd is a runtime requirement on musl builds and was historically
# missing from the inherited packaging's dependency list.
# linux-pam: Saphira platform policy builds openssh --with-pam.
# saphira-pambase: the sshd service includes system-remote-login.
depends="
    libmd
    linux-pam
    saphira-base-accounts
    saphira-pambase
    zlib
"

makedepends="
    binutils
    gawk
    gcc
    make
    libmd-dev
    linux-pam-dev
    openssl-dev
    pkgconf
    zlib-dev
"

replaces="openssh-client openssh-server"
subpackages="openssh-doc"
recipe_build()
{
	# Saphira OpenSSH/network policy (IPv6-first, PAM, shadow):
	# explicit FHS paths; sshd:/var/empty privilege separation;
	# pid in /var/run/sshd (sshd runs from /usr/sbin, so /var/run;
	# r8 adopted from hotfix/var-packaging-bug-var-run-isnot-run);
	# PAM on (platform provides linux-pam); 4in6
	# mapped-address handling on; no SELinux/RPATH. Shadow stays
	# at upstream default (enabled) - never --without-shadow.
	# Every flag proven against 10.5p1 ./configure --help.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc/ssh \
		--localstatedir=/var \
		--libexecdir=/usr/lib/ssh \
		--runstatedir=/run \
		--with-privsep-user=sshd \
		--with-privsep-path=/var/empty \
		--with-pid-dir=/var/run/sshd \
		--with-pam \
		--with-4in6 \
		--without-selinux \
		--without-rpath
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
	# PAM service entry: linux-pam ships no service files and
	# saphira-pambase ships only the shared stacks; each service
	# owns its own /etc/pam.d entry (mirrors accounts.d).
	# Without this, UsePAM yes would deny all logins.
	install -D -m 0644 "$RECIPE_DIR/files/pam.d/sshd" \
		"$PKGDEST/etc/pam.d/sshd"
	find "$PKGDEST/etc/ssh" -type f -name 'ssh_host_*' -delete
	# 10.5p1: ssh-keygen -A also emits ssh_host_mldsa44_ed25519_key
	# (USE_MLDSA, on for gcc builds); sshd_config lists it first.
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

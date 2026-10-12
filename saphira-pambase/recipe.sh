#!/bin/sh

pkgname=saphira-pambase
pkgver=1.0
pkgrel=3
# r3: /etc/security/namespace.conf (empty default is MANDATORY:
# pam_namespace fails closed when its config is missing, and
# systemd-user/run0 call it as required - every logind session
# would fail without it). Payload change, bumps.
# r2: /etc/shells (pam_shells fails closed without it - proven in
# module source) + /etc/security/limits.d/10-saphira.conf (fork-bomb
# nproc cap, classic nofile pair). Payload change, bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira Linux PAM default stacks (system-auth/login/services, deny-all other)'
license='BUSL-1.1'
origin=saphira-pambase
repo=saphira
url=https://saphira.vm2.uk/

# Shared PAM stacks in the Arch pambase shape, adapted to Saphira's
# shipped module set: no pam_systemd_home (no homed provider),
# no pam_lastlog2 (util-linux builds lastlog2-disabled), no pam_rhosts
# consumers (inetutils stays PAM-less). systemd session lines are
# dash-optional, so one file serves OpenRC and systemd alike.
# Leaf service files live in their own packages (shadow, sudo,
# openssh, dovecot, cronie) mirroring the accounts.d single-owner rule;
# systemd's own /usr/lib/pam.d + factory copies are separate paths.
# Deliberately UNSHIPPED (proven safe from the 1.7.2 module sources):
# access.conf (missing table = no access control, allow), time.conf
# (no rules = allow), pam_env files (missing = IGNORE, passes
# required), limits.conf (missing = PAM defaults; policy lives in
# limits.d/10-saphira.conf below). Only /etc/shells is mandatory.
depends="
    linux-pam
"

makedepends=""

# Local payload: no upstream source/archive to invent (package-template
# 3b precedent). url= above is the Saphira-originals metadata contract.
recipe_build()
{
	# No build: validate every shipped file exists.
	for f in system-auth system-login system-local-login \
		system-remote-login system-services other; do
		test -f "$RECIPE_DIR/files/pam.d/$f"
	done
	test -f "$RECIPE_DIR/files/shells"
	test -f "$RECIPE_DIR/files/security-limits.d/10-saphira.conf"
	test -f "$RECIPE_DIR/files/security-namespace.conf"
}

recipe_install()
{
	for f in system-auth system-login system-local-login \
		system-remote-login system-services other; do
		install -D -m 0644 "$RECIPE_DIR/files/pam.d/$f" \
			"$PKGDEST/etc/pam.d/$f"
	done
	# Valid login shells: world-readable, never world-writable
	# (pam_shells refuses either violation and fails closed).
	install -D -m 0644 "$RECIPE_DIR/files/shells" \
		"$PKGDEST/etc/shells"
	# Default resource policy (numeric prefix: an admin
	# 99-local.conf sorts after 10-saphira.conf and overrides).
	install -D -m 0644 \
		"$RECIPE_DIR/files/security-limits.d/10-saphira.conf" \
		"$PKGDEST/etc/security/limits.d/10-saphira.conf"
	# Polyinstantiation table: empty default, but the file must
	# exist (see the header comment in the file itself).
	install -D -m 0644 "$RECIPE_DIR/files/security-namespace.conf" \
		"$PKGDEST/etc/security/namespace.conf"
}

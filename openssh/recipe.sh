#!/bin/sh

pkgname=openssh
pkgver=10.6_p1
pkgrel=7
# r6: sshd -t gates the start (2026-10-23: a corrupt mldsa44 host-key
# pair, broken since 2026-10-17 while the type was never served, failed
# validation while sshd started degraded -- the check logged but did not
# gate. start_pre now returns 1 on -t failure; proven by the corrupt-key
# case in tests/sshd-hostkeys.sh. Existing keys are never regenerated,
# only missing types (ssh-keygen -A unchanged). Payload change.
# r5: login accounting via libc headers, not configure overrides
# (2026-10-23, proven by r4: CONF_WTMP/CONF_UTMP/CONF_LASTLOG defines
# are DEAD whenever libc headers define the macros -- openssh defines.h
# prefers _PATH_* and musl's utmp.h pointed them at /dev/null, so r4
# shipped the env pins, passed its config.h assert, and still wrote
# /dev/null/wtmp. musl 0003 now carries the real paths in utmp.h too;
# the recipe pins nothing and instead asserts the built session binary
# references the real databases. Service-side DB creation unchanged).
# r4: login accounting paths (2026-10-23, proven by sshd-session errors
# on Egg: "wtmp_write: problem writing /dev/null/wtmp" + missing
# /var/log/lastlog). musl's <utmp.h> deliberately neuters WTMP_FILE and
# UTMP_FILE to /dev/null/*, and configure trusts the system macro, so
# the compiled sshd wrote accounting into /dev/null. All three pinned
# explicitly (lastlog via its flag; wtmp/utmp have no flag, so set
# configure's own location variables in its environment), proven in
# config.h fail-closed below, plus the shipped empty lastlog database
# (sshd never creates it). Payload change.
# r3: --with-default-path sets the canonical PATH for sshd sessions
# (upstream default omits /usr/local and interleaves the pairs;
# verified in 10.6 defines.h, flag verified in configure.ac). Same
# value for root (SUPERUSER_PATH follows). Payload change.
# r2 (via bumppkg, builder already staged r1): stop offering the RSA
# host key (sshd_config now mldsa44 > ed25519 > ecdsa; client-side
# RSA untouched). Payload change.
# r1: upstream 10.6p1 (2026-10-06). All configure flags revalidated
# against 10.6 ./configure --help (privsep-user/path, pid-dir, pam,
# 4in6, libexecdir, runstatedir, without-selinux/rpath all present;
# the removed --disable-fd-passing was never used). USE_MLDSA still
# compiler-gated in defines.h (VLA + mixed declarations: gcc has
# both), so ssh-keygen -A still emits the mldsa44 host key.
# Provenance: TLS fetch from cdn.openbsd.org + release signature by
# key 7168B983815A5EEF59A4ADFD2A3F414E736060BA (matches the published
# portable fingerprint; local gpg keyboxd unavailable for full verify)
# + hex sha256 pin.
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
source=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.6p1.tar.gz
sha256=a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39

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
	# Login accounting paths are NOT pinned here: musl's headers are
	# the single source of truth (defines.h prefers _PATH_* over any
	# CONF_* override, so configure pins are silently dead -- proven
	# by r4). musl 0003 carries the real paths in paths.h and utmp.h;
	# the install step below asserts the built binary references them.
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
		--without-rpath \
		--with-default-path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install-nokeys
	# True accounting contract (see r5 header): the staged session
	# binary must reference the real databases and never musl's old
	# neutering. This asserts the linked result in the payload, not a
	# config.h intermediate that the headers can silently override --
	# an assert in recipe_build runs before install stages anything.
	# NOTE: never `strings ... | grep -Fq` over a large binary here:
	# grep -q quits at the first match, strings then dies on SIGPIPE,
	# and under set -o pipefail the pipeline reports failure despite
	# the match (proven 2026-10-23: grep -c said 1 while -q missed on
	# the same file). grep -c consumes the whole stream, so no writer
	# is ever cut off and the result is deterministic.
	for needle in /var/log/wtmp /var/log/lastlog; do
		[ "$(strings -a "$PKGDEST/usr/lib/ssh/sshd-session" | grep -F -c "$needle")" -gt 0 ] || {
			echo "ERROR: sshd-session omits $needle (libc accounting headers?)" >&2
			return 1
		}
	done
	if [ "$(strings -a "$PKGDEST/usr/lib/ssh/sshd-session" | grep -F -c '/dev/null/wtmp')" -gt 0 ]; then
		echo "ERROR: sshd-session references /dev/null/wtmp" >&2
		return 1
	fi
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
	# 10.6p1: ssh-keygen -A also emits ssh_host_mldsa44_ed25519_key
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

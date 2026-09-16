#!/bin/sh

pkgname=qmail
pkgver=2026.09.08_rc1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="qmail MTA core, toasterDragon resurrected (sagredo tree, chkuser against vpopmail)"
# No LICENSE file ships in-tree. Vanilla qmail-1.03/netqmail-1.06 is
# public-domain (DJB); this tree layers ~40 third-party patches
# (AUTH/TLS/SRS/SPF/DKIM/DNSBL/...) whose terms are mixed and several
# undeclared. LicenseRef until the full patch audit lands; never a
# bare public-domain claim for the stack.
license="LicenseRef-Sagredo-qmail-stack"
origin=qmail
repo=main
url=https://github.com/sagredo-dev/qmail
# Pinned commit of the sagredo-dev/qmail main branch (VERSION file at
# the pin reads 2026.09.08-rc.1, recorded here Alpine-style as
# 2026.09.08_rc1: apk forbids interior dashes, and its suffix grammar
# wants _rc1, not _rc.1 (probed via apk mkpkg); full SHA in source=.
source=https://github.com/sagredo-dev/qmail/archive/466192b9664c61d6248e9096f9f7810375a1dd15.tar.gz
sha256=3ff755eb25bba56127db635a11621e022f86ce9e271ff0082954552ae415d891

depends="
    libsrs2
    libidn2
    libxcrypt
    mariadb
    openssl
    vpopmail
    zlib
"

makedepends="
    binutils
    gawk
    gcc
    groff
    libidn2-dev
    libsrs2-dev
    libxcrypt-dev
    make
    mariadb-dev
    openssl-dev
    pkgconf
    vpopmail-dev
    zlib-dev
"

recipe_build()
{
	# Staging patch (see files/saphira-staging.patch): fixed
	# build-time identities (accounts.d/qmail 132-142, rootless
	# builders cannot getpwnam) and DESTDIR + SAPHIRA_NO_CHOWN in
	# install.c (ownership applies at install via the fragment).
	patch -p1 < "$RECIPE_DIR/files/saphira-staging.patch"
# DJB conf files: toolchain plus the vpopmail header path (the
# -dev split relocates them to /usr; VPOPMAIL_LIBS still comes
# from vpopmail's own lib_deps flag file, whose auth_libs+LIBS
# drag in mysqlclient, z and crypt - hence mariadb-dev, zlib-dev
# and libxcrypt-dev below, mirroring vpopmail's own closure).
	printf '%s\n' 'gcc -O2 -pipe -g -std=gnu17' > conf-cc
	printf '%s\n' 'gcc -g' > conf-ld
	# chkuser always compiles on main; VPOPMAIL_DIR/INC overridden
	# (the Makefile would getent-resolve them, which needs the live
	# users - same rootless constraint as the UID probe).
	# man target included: hier.c installs the generated cat pages
	# (man/cat*) unconditionally, but only `it` is the default build
	# and nroff (groff) renders them.
	make -j${JOBS:-$(nproc)} it man \
		VPOPMAIL_DIR=/home/vpopmail \
		VPOPMAIL_INC=-I/usr/include/vpopmail
}

recipe_install()
{
	cd "$SRC"
	# install(1)-style single mkdir needs the DESTDIR parents to
	# exist (true on real roots, not in staging).
	mkdir -p "$PKGDEST/var" "$PKGDEST/usr"
	DESTDIR="$PKGDEST" SAPHIRA_NO_CHOWN=1 ./install
	# The queue trigger fifo must not ship: APK payloads carry
	# regular files only (apk mkpkg blocks opening a fifo forever),
	# and the fragment documents the split - qmail-send.service
	# creates it with ownership at start, idempotently.
	rm -f "$PKGDEST/var/qmail/queue/lock/trigger"
	# Man pages belong in /usr/share/man (never /var/qmail/man);
	# upstream troff sources install as-is, rendered on demand.
	for s in 1 5 7 8; do
		mkdir -p "$PKGDEST/usr/share/man/man$s"
		for m in "$SRC"/*.$s; do
			[ -f "$m" ] || continue
			install -m 0644 "$m" "$PKGDEST/usr/share/man/man$s/"
		done
	done
	# Closed localhost control seed (admin provisions their domain
	# with the config-fast equivalent afterwards; SRS stays disabled
	# until then - no secret is ever shipped).
	ctl="$PKGDEST/var/qmail/control"
	printf '%s\n' 'localhost' > "$ctl/me"
	printf '%s\n' 'localhost' > "$ctl/defaultdomain"
	printf '%s\n' 'localhost' > "$ctl/plusdomain"
	printf '%s\n' 'localhost' > "$ctl/locals"
	printf '%s\n' 'localhost' > "$ctl/rcpthosts"
	printf '%s\n' "| /home/vpopmail/bin/vdelivermail '' delete" > "$ctl/defaultdelivery"
	printf '%s\n' '200' > "$ctl/concurrencyincoming"
	printf '%s\n' 'localhost' > "$ctl/bouncehost"
	printf '%s\n' '20000000' > "$ctl/databytes"
	printf '%s\n' '272800' > "$ctl/queuelifetime"
	printf '%s\n' '30000000' > "$ctl/softlimit"
	printf '%s\n' '100' > "$ctl/maxrcpt"
	printf '%s\n' '2' > "$ctl/brtlimit"
	printf '%s\n' '3' > "$ctl/spfbehavior"
	printf '%s\n' 'HIGH:MEDIUM:!MD5:!RC4:!3DES:!LOW:!SSLv2:!SSLv3' > "$ctl/tlsserverciphers"
	cat > "$ctl/smtpplugins" <<'EOF'
# smtpplugins sample file
[connection]

[auth]

[helo]

[mail]

[rcpt]

[pass]

[data]
EOF
	# Explicit file modes (umask-independent); directory modes come
	# from install and must stand (domainkeys is 0700).
	find "$ctl" -maxdepth 1 -type f -exec chmod 0644 {} +
	# Local aliases: postmaster trio (SRS aliases arrive with SRS
	# enablement, never before).
	al="$PKGDEST/var/qmail/alias"
	printf '%s\n' 'postmaster@localhost' > "$al/.qmail-postmaster"
	ln -sf .qmail-postmaster "$al/.qmail-mailer-daemon"
	ln -sf .qmail-postmaster "$al/.qmail-root"
	chmod 0644 "$al"/.qmail-*
	install -D -m 0644 "$RECIPE_DIR/files/qmail-send.service" \
		"$PKGDEST/usr/lib/systemd/system/qmail-send.service"
	install -D -m 0755 "$RECIPE_DIR/files/qmail-send.initd" \
		"$PKGDEST/etc/init.d/qmail-send"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/qmail" \
		"$PKGDEST/usr/share/saphira/accounts.d/qmail"
	# instcheck is deliberately not run: it verifies live ownership
	# that rootless staging cannot provide. Its expectations (same
	# hier.c) are encoded in the fragment above instead, and the
	# reconciler enforces them at install.
}

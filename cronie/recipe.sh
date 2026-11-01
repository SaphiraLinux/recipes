#!/bin/sh
pkgname=cronie
pkgver=1.7.2
pkgrel=2
# Unbumped r3->r2 (operator rule): only bump over a PUBLISHED revision.
# r2 never published (r1 live), so the PAM-headers fix stays r2.
# r2: PAM enabled (linux-pam 1.7.2 + saphira-pambase now in tree):
# --with-pam; ships the crond leaf file. Sole cron (dcron retired,
# same /usr/sbin/crond + man pages, cannot coexist). Payload change,
# revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Standard cron daemon with anacron support'
license='MIT BSD-2-Clause'
origin=cronie
repo=saphira
url=https://github.com/cronie-crond/cronie
cronie_sha256=241ecc1dcd8d4b2a6744fe93509932254d20b7bb9d979d27429809493806357f
# Sole cron: dcron retired (same /usr/sbin/crond + man pages, cannot
# coexist). replaces takes the legacy names over on upgrade.
# linux-pam: linked at build (headers in linux-pam-dev) and needed
# at runtime.
replaces="dcron dcron-doc"
depends="linux-pam saphira-pambase"
makedepends="autoconf automake gcc linux-pam-dev make saphira-linux-uapi-headers"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/cronie-1.7.2.tar.gz"
	cd "$SRC"
	echo "$cronie_sha256  $RECIPE_DIR/files/cronie-1.7.2.tar.gz" | sha256sum -c -
	autoreconf -fi "$SRC"
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0001-load_entry-error_func-prototype-c23.patch"
	# gcc16/C23 makes incompatible-pointer-types an error; cronie 1.7.2
	# passes mismatched fn pointers to load_entry
	# No --without-systemd. It was here because upstream's unit was
	# considered unwanted, but cronie is the SOLE cron (replaces dcron,
	# which is disabled) and shipped no service definition in either
	# format, so the host had no way to start it at all. The house unit
	# is packaged either way; upstream's own is parked like the sysv
	# scripts, so both formats come from files/ and this flag only
	# decided whether a duplicate appeared.
	CFLAGS="${CFLAGS-} -Wno-incompatible-pointer-types -Wno-error=incompatible-pointer-types -Wno-error=declaration-missing-parameter-type" ./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-pam --without-selinux --without-audit \
		--with-inotify --enable-anacron \
		--with-systemdsystemunitdir=no
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# PAM service entry (saphira-pambase carries the shared stacks).
	install -D -m 0644 "$RECIPE_DIR/files/pam.d/crond" \
		"$PKGDEST/etc/pam.d/crond"
	# Dual-init policy: both definitions ship unconditionally, neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/crond.initd" \
		"$PKGDEST/etc/init.d/crond"
	install -D -m 0644 "$RECIPE_DIR/files/crond.service" \
		"$PKGDEST/usr/lib/systemd/system/crond.service"
	# The spool must exist and be private before crond ever runs.
	install -d -m 0700 "$PKGDEST/var/spool/cron" "$PKGDEST/var/spool/cron/crontabs"
	# Upstream installs no init script with our flags
	# (--with-systemdsystemunitdir=no, no sysv target), so there is
	# nothing to park: the rm that stood here deleted our own
	# etc/init.d/crond installed above and tripped the gate below.
	for p in etc/init.d/crond usr/lib/systemd/system/crond.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: cronie payload is missing $p" >&2
			return 1
		}
	done
}

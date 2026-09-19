#!/bin/sh
pkgname=logrotate
pkgver=3.22.0
# r3: complete Saphira facility, not just the binary. Ships the
# master config (weekly/rotate-4/create/dateext/compress + include
# logrotate.d), standard file-log snippets (apk, nginx with
# reopen-not-copytruncate, php-fpm, rsyncd, wtmp, lastlog),
# systemd service + daily persistent timer, OpenRC one-shot plus a
# cron.daily script for cronie/anacron parity. Deliberately absent:
# /var/log/messages (no logger writes it), anything under
# /var/log/journal (journald retention owns that). r4: service
# snippets migrate to their owner recipes per the logrotate.d
# convention (nginx, php-fpm, rsyncd, apk all moved out); this
# package keeps the master config, scheduling, and the ownerless
# generics (wtmp, lastlog) only.
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Rotates, compresses, and mails system logs'
license='GPL-2.0-or-later'
origin=logrotate
repo=saphira
url=https://github.com/logrotate/logrotate
logrotate_sha256=f55b0f105f8ff145ea5b98166247d0c5d107f7fa8e8708130a2213dbde992db9
depends="popt acl attr"
makedepends="autoconf automake popt-dev acl-dev attr-dev gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/logrotate-3.22.0.tar.gz"
	cd "$SRC"
	echo "$logrotate_sha256  $RECIPE_DIR/files/logrotate-3.22.0.tar.gz" | sha256sum -c -
	autoreconf -fi
	./configure --prefix=/usr --disable-static --with-acl \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--without-selinux --without-systemd
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.conf" \
		"$PKGDEST/etc/logrotate.conf"
	for snippet in wtmp lastlog; do
		install -D -m 0644 "$RECIPE_DIR/files/logrotate.d-$snippet" \
			"$PKGDEST/etc/logrotate.d/$snippet"
	done
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.service" \
		"$PKGDEST/usr/lib/systemd/system/logrotate.service"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.timer" \
		"$PKGDEST/usr/lib/systemd/system/logrotate.timer"
	install -D -m 0755 "$RECIPE_DIR/files/logrotate.initd" \
		"$PKGDEST/etc/init.d/logrotate"
	install -D -m 0755 "$RECIPE_DIR/files/logrotate.cron-daily" \
		"$PKGDEST/etc/cron.daily/logrotate"
	# The package ships rules, never log content: no /var/log
	# payload, nothing journal-related.
	if find "$PKGDEST/var" -type f 2>/dev/null | grep -q .; then
		echo "ERROR: log content staged under var/" >&2; return 1
	fi
	grep -rq journal "$PKGDEST/etc/logrotate" "$PKGDEST/etc/logrotate.d" && {
		echo "ERROR: journal path referenced in rotation rules" >&2; return 1; } || true
	test -f "$PKGDEST/etc/logrotate.conf" || {
		echo "ERROR: master logrotate.conf missing" >&2; return 1; }
}

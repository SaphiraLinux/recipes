#!/bin/sh

pkgname=saphira-build-dashboard
pkgver=1.0
pkgrel=7
# r2: stage the accounts.d fragment into the payload (r1 shipped no
# identity scripts: makepkg generates ONLY from the payload copy at
# usr/share/saphira/accounts.d/<name>, and the r1 recipe never staged
# it there - proven by adbdump-vs-gpsd. Payload proof asserts the
# staged fragment, gpsd idiom). Payload change.
# r1: initial publication. Read-only IPv4 build-queue dashboard: TODAY (/)
# and History (/history) views over the saphira-build queue database,
# served on 172.16.7.5:8899 by default. Bind/port/db are per-machine
# config via /etc/conf.d/saphira-build-dashboard (OpenRC sources it
# when present; the package ships none, so updates never fight the
# admin's choice). Separately packaged by design, never part
# of saphira-packager: the observer must not share fate with the
# controller it observes. Read-only by construction - GET/HEAD only
# (anything else is 405), SQLite opened mode=ro, no writes, no
# subprocesses, no state directory. Runs as its own dashboard:178
# identity (first free ID above 177 plugdev; accounts.tsv carries no
# 178-199 and no tree fragment claims one), both inits shipped
# unconditionally, never enabled or started on install.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Read-only build queue dashboard (TODAY/History on 172.16.7.5:8899)"
license="BUSL-1.1"
origin=saphira-build-dashboard
repo=main
url=https://saphira.vm2.uk/

# The server is Python 3 stdlib only (http.server + sqlite3): no third
# party modules, so python3 is the entire runtime closure.
depends="python3"

makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-build-dashboard" \
		"$PKGDEST/usr/sbin/saphira-build-dashboard"
	install -D -m 0755 "$RECIPE_DIR/files/saphira-build-dashboard.initd" \
		"$PKGDEST/etc/init.d/saphira-build-dashboard"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-build-dashboard.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-build-dashboard.service"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-build-dashboard/LICENSE"
	# Service identity declaration (dashboard:178); makepkg generates
	# the install/upgrade scripts ONLY from this payload copy - a
	# tree fragment alone ships nothing (r1 proved it: no scripts).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-build-dashboard" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-build-dashboard"
	# Payload proof: every shipped path asserted, so a dropped install
	# line fails the build instead of shipping a userless daemon.
	for p in usr/sbin/saphira-build-dashboard \
		etc/init.d/saphira-build-dashboard \
		usr/lib/systemd/system/saphira-build-dashboard.service \
		usr/share/saphira/accounts.d/saphira-build-dashboard \
		usr/share/licenses/saphira-build-dashboard/LICENSE; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: saphira-build-dashboard payload is missing $p" >&2
			return 1
		}
	done
}

#!/bin/sh

pkgname=saphira-utmp
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira boot-time utmp/wtmp accounting (one BOOT_TIME record per boot)"
license='BUSL-1.1'
origin=saphira-utmp
repo=saphira
url=https://saphira.vm2.uk/

depends=""

makedepends="
    gcc
"

# Neither init path writes utmp/wtmp records on Saphira (OpenRC has
# no utmp writer; systemd is built -Dutmp=false, musl-mandated), so
# coreutils uptime/who -b fell back to image-file mtimes. The
# recorder writes exactly one BOOT_TIME record per kernel boot,
# keyed on the kernel's own btime (never invented, never system
# clock), and no-ops on re-run. Dual-init like every other daemon
# package (service is inert unless the image enables it); the tool
# itself runs as root with no new identity (it only ever writes the
# two root-owned accounting files).
recipe_build()
{
	# Plain gcc (not $CC): the builder does not export CC, and
	# set -u turns the reference into a hard failure.
	gcc -std=c11 -O2 -Wall -Wextra -Werror \
		-o "$BUILDDIR/saphira-utmp-boot" \
		"$RECIPE_DIR/files/saphira-utmp-boot.c"
	# Build-time smoke: --help must work without touching the
	# accounting files; anything else is a usage error. Behaviour
	# itself is proven hermetically in tests/utmp-boot.sh (scratch
	# root via SAPHIRA_UTMP_ROOT, validated with utmpdump and the
	# real coreutils who/uptime against scratch files).
	"$BUILDDIR/saphira-utmp-boot" --help >/dev/null || {
		echo "ERROR: saphira-utmp-boot --help failed" >&2
		return 1
	}
	# A deliberately bad flag must fail (usage error, exit 2).
	# Written as if/then, not cmd && fail: under set -e a failing
	# trailing &&-list aborts the build with the *expected* status
	# instead of reaching the failure report.
	if "$BUILDDIR/saphira-utmp-boot" --bogus-flag >/dev/null 2>&1; then
		echo "ERROR: saphira-utmp-boot accepted a bogus flag" >&2
		return 1
	fi
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/saphira-utmp-boot" \
		"$PKGDEST/usr/sbin/saphira-utmp-boot"
	install -D -m 0755 "$RECIPE_DIR/files/saphira-utmp-boot.initd" \
		"$PKGDEST/etc/init.d/saphira-utmp-boot"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-utmp-boot.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-utmp-boot.service"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-utmp/LICENSE"
	for f in \
		usr/sbin/saphira-utmp-boot \
		etc/init.d/saphira-utmp-boot \
		usr/lib/systemd/system/saphira-utmp-boot.service \
		usr/share/licenses/saphira-utmp/LICENSE \
	; do
		[ -e "$PKGDEST/$f" ] || {
			echo "ERROR: saphira-utmp payload is missing $f" >&2
			return 1
		}
	done
}

#!/bin/sh

pkgname=saphira-init-switch
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenRC <-> systemd init-swap network migration (MAC-anchored translator)'
license='BUSL-1.1'
origin=saphira-init-switch
repo=main
url=https://saphira.vm2.uk/

# Local payload: the migration script, runbook and license below.
# No upstream source exists; do not invent one.
depends="iproute2"
makedepends=""

recipe_build()
{
	# Shell only: syntax-check the payload. Behaviour is covered by
	# tests/migrate.sh (hermetic fixtures, no live network needed).
	sh -n "$RECIPE_DIR/files/saphira-net-migrate"
	sh -n "$RECIPE_DIR/files/saphira-init-switch"
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-net-migrate" \
		"$PKGDEST/usr/sbin/saphira-net-migrate"
	install -D -m 0755 "$RECIPE_DIR/files/saphira-init-switch" \
		"$PKGDEST/usr/sbin/saphira-init-switch"
	install -D -m 0644 "$RECIPE_DIR/files/RUNBOOK" \
		"$PKGDEST/usr/share/doc/saphira-init-switch/RUNBOOK"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-init-switch/LICENSE"
}

#!/bin/sh

pkgname=saphira-maildragon
pkgver=0.2
pkgrel=5
# r4: rspamd antivirus backend socket aligned to the real clamd
# LocalSocket (/var/run/clamav/clamd.sock - the old path was wrong
# on both axes: dir and filename). Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="mailDragon: sqlite-backed mail stack glue for Saphira (postfix/dovecot/rspamd/clamav)"
license="BUSL-1.1"
origin=saphira-maildragon
repo=main
url=https://saphira.vm2.uk/

# Glue metapackage: binaries/services live in their own packages; this
# ships the ported v0 configuration set, management scripts and schema.
depends="
    clamav-daemon
    clamav-freshclam
    dovecot
    postfix
    postfix-sqlite
    python3
    rspamd
"

recipe_build()
{
	:
}

recipe_install()
{
	install -d -m 0755 \
		"$PKGDEST/usr/share/saphira/maildragon/etc/rspamd" \
		"$PKGDEST/usr/lib/systemd/system"
	# NOTE (aa8ef66c, 2026-08-27): the database/*.sql schema and the
	# files/scripts/* tools were deliberately stripped pending the
	# recovered five-package split (core/scripts/db) - the install
	# loops referencing them were removed with the content. This
	# interim glue ships configs only; scripts+schema return with
	# the split. Do not re-add either loop without the content.
	for f in "$RECIPE_DIR"/files/etc/sqlite-*.cf \
	         "$RECIPE_DIR"/files/etc/main.cf.maildragon; do
		install -m 0644 "$f" \
			"$PKGDEST/usr/share/saphira/maildragon/etc/"
	done
	for f in dovecot-sql.conf.ext dovecot-maildragon.conf antivirus.conf \
	         classifier-bayes.conf composites.conf dkim_signing.conf \
	         greylist.conf milter_headers.conf multimap.conf redis.conf \
	         worker-proxy.inc worker-controller.inc; do
		[ -f "$RECIPE_DIR/files/etc/$f" ] && install -m 0644 \
			"$RECIPE_DIR/files/etc/$f" \
			"$PKGDEST/usr/share/saphira/maildragon/etc/"
	done
	install -m 0644 "$RECIPE_DIR/files/maildragon-setup.service" \
		"$PKGDEST/usr/lib/systemd/system/maildragon-setup.service"
	# Dual-init policy: the oneshot is invoked as a service on both init
	# systems, so it gets an OpenRC equivalent too - "oneshot" is not an
	# exemption.  Nothing is auto-enabled at install.
	install -d -m 0755 "$PKGDEST/etc/init.d"
	install -m 0755 "$RECIPE_DIR/files/maildragon-setup.initd" \
		"$PKGDEST/etc/init.d/maildragon-setup"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-maildragon/LICENSE"
}

#!/bin/sh

pkgname=saphira-mail
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira mail-server group (postfix, dovecot, rspamd, clamav, maildragon glue)'
license='BUSL-1.1'
origin=saphira-mail
repo=saphira
url=https://saphira.vm2.uk/

# Metapackage: carries no payload of its own. The member list lives in
# depends= below and is resolved by the package manager at install
# time. Profiles and image definitions name this group; they must
# never re-enumerate its closure. The reference saphira-mail admin
# shell is superseded: its duties live in saphira-maildragon
# (configs, scripts, schema) plus the member daemons below.
depends="
	clamav
	clamav-daemon
	clamav-freshclam
	dovecot
	postfix
	rspamd
	saphira-maildragon
"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/README.group" \
		"$PKGDEST/usr/share/doc/saphira-mail/README.group"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-mail/LICENSE"
}

#!/bin/sh

pkgname=saphira-tools
pkgver=0.1
pkgrel=3
# r3: saphira-site generated pools/vhosts use /var/run/php-fpm85/
# (were unversioned /run/php-fpm/, wrong even before the php85
# r2 move). Generated pools land in php-fpm.d; the socket dir
# lifecycle belongs to the php85 package. Payload change, revision
# bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira site provisioning tool (nginx vhost + php-fpm pool setup)"
license="BUSL-1.1"
origin=saphira-tools
repo=saphira
url=https://saphira.vm2.uk/

depends="
    nginx
    php85
"

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-site" \
		"$PKGDEST/usr/sbin/saphira-site"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-tools/LICENSE"
}

#!/bin/sh

pkgname=saphira-image-firstboot
pkgver=0.1
pkgrel=5
# r5: bounded by-id poll (30s) before failing closed.
# Payload change.
# r4: systemd appliance: wizard unit replaces the openrc initd
# (removed). Payload change.
# r3: installer typescript via script(1): a failed run leaves
# /var/log/saphira-installer.log instead of failing silent into a
# login prompt. Payload change.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Dedicated installer wizard for the USB creator appliance'
license='BUSL-1.1'
origin=saphira-image-firstboot
repo=saphira
url=https://saphira.vm2.uk/

depends="
    dialog
    saphira-image-creator
    saphira-install-tools
    saphira-network
    dhcpcd
    util-linux
"

makedepends=""

recipe_build()
{
	sh -n "$RECIPE_DIR/files/saphira-firstboot-image" ||
		{ echo "ERROR: wizard syntax check failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/image-firstboot.sh" ||
		{ echo "ERROR: image-firstboot suite failed" >&2; return 1; }
	:
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-firstboot-image" \
		"$PKGDEST/sbin/saphira-firstboot-image"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-firstboot-image.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-firstboot-image.service"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-firstboot-image.8" \
		"$PKGDEST/usr/share/man/man8/saphira-firstboot-image.8"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-image-firstboot/LICENSE"
}

#!/bin/sh

pkgname=saphira-virtualisation
pkgver=0.1
pkgrel=3
# noarch: pure meta/profile package (no payload of its own beyond group
# docs). Arch-specific members in depends= do not make the group itself
# arch-specific; noarch groups publish arch: noarch inside the per-arch
# repo dir (proven by python-jinja2 and kin), so no noarch/ subdir is
# needed. Payload change (arch field), hence the revision bump.
pkgarch=noarch
pkgdesc='Saphira virtualisation group (QEMU host emulation plus libvirt management)'
license='BUSL-1.1'
origin=saphira-virtualisation
repo=saphira
url=https://saphira.vm2.uk/

# Metapackage: carries no payload of its own. The member list lives in
# depends= below and is resolved by the package manager at install
# time. Profiles and image definitions name this group; they must
# never re-enumerate its closure (no QEMU/libvirt plumbing knowledge
# outside APK metadata).
depends="
	libvirt
	qemu
"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/README.group" \
		"$PKGDEST/usr/share/doc/saphira-virtualisation/README.group"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-virtualisation/LICENSE"
}

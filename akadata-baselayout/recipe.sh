#!/bin/sh

# RETIRED package name. akadata-baselayout is superseded by
# saphira-baselayout (Genesis rebrand, r2 there carries the payload-path
# migration: sbin/saphira-firstboot, /usr/libexec/saphira,
# /var/lib/saphira-firstboot, SAPHIRA_FIRSTBOOT_* env prefixes). This
# recipe exists only so the builder records a deliberate, documented
# skip. Consumers must depend on saphira-baselayout.

pkgname=akadata-baselayout
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='RETIRED akadata filesystem skeleton (superseded by saphira-baselayout)'
license='MIT'
origin=akadata-baselayout
repo=saphira
url=https://saphira.vm2.uk/

disabled=yes
disabled_reason='renamed to saphira-baselayout; Genesis rebrand'

recipe_build()
{
	echo "ERROR: akadata-baselayout is disabled: $disabled_reason" >&2
	return 1
}

recipe_install()
{
	echo "ERROR: akadata-baselayout is disabled: $disabled_reason" >&2
	return 1
}

#!/bin/sh

pkgname=saphira-base
pkgver=0.1
pkgrel=3
# x86_64, not noarch: apk-tools v3 fetches noarch payloads from a
# per-arch noarch/ subdir that the Saphira repo layout does not
# publish yet (verified 2026-09-08: hatched/noarch/ absent, fetch
# ENOENT). Revisit noarch if that layout lands; the closure is
# arch-specific anyway.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira base group (ABI marker, layout, libc, shell, account and package tooling)'
license='BUSL-1.1'
origin=saphira-base
repo=saphira
url=https://saphira.vm2.uk/

# Metapackage: carries no payload of its own. The member list lives in
# depends= below and is resolved by the package manager at install
# time. Profiles and image definitions name this group; they must
# never re-enumerate its closure. Deliberately kernel-agnostic and
# init-neutral: the profile owns the kernel and init-system choice.
depends="
	apk-tools
	bash
	ca-certificates
	coreutils
	musl
	saphira-base-abi
	saphira-baselayout
	shadow
	util-linux
"
makedepends=""

recipe_build()
{
	:
}

recipe_install()
{
	install -D -m 0644 "$RECIPE_DIR/files/README.group" \
		"$PKGDEST/usr/share/doc/saphira-base/README.group"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-base/LICENSE"
}

#!/bin/sh

pkgname=saphira-memoryd
# Version follows the source (SAPHIRA_VERSION) once the repository
# has content; the placeholder below is revisited at release.
pkgver=0.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira Memory daemon (SHAMPOO discovery)"
# The recipe field states the package terms (BUSL-1.1, as published;
# see files/LICENSE for the WinRAR-style use grant: the software is
# free, commercial use requires a purchased licence, no liability,
# own risk). The build source itself stays private until the
# repository is opened publicly; source is available on request.
license="BUSL-1.1"
origin=saphira-memoryd
repo=saphira
url=https://saphira.vm2.uk/
# No source=/vendor=/sha256= lines by decision: the source must
# NEVER become part of /recipes (not vendored, not verified here).
# The build clones the private repository below at build time
# instead. The git: form is deliberate (SSH, never https).
gitsource="git@github.com:SaphiraLinux/shampoo.git"
gitbranch="Master"

depends="
    json-c
    mariadb
    openssl
"
makedepends="
    binutils
    gcc
    git
    json-c-dev
    make
    mariadb-dev
    openssl-dev
    pkgconf
"
subpackages="$pkgname-doc"

# Release gate: the recipe exists so the packaging shape is reviewed
# and ready, but the product is NOT released. disabled=yes makes
# every builder refuse it (resolvepkg fails closed, buildpkg
# refuses) until this line is deliberately removed at release. No
# build, no staging, no publication can happen through the
# machinery while it stands. The startup nag and delay live in the
# source itself (built there, not here); no clone or test happens
# until release either.
disabled=yes
disabled_reason='saphira-memoryd unreleased: private source, recipe held for review; remove at release decision only'

recipe_build()
{
	# Clone the private source to /build/saphira-memoryd at build
	# time. Nothing is fetched before this point and nothing is
	# stored in the recipe tree.
	rm -rf /build/saphira-memoryd
	git clone --branch "$gitbranch" --depth 1 \
		"$gitsource" /build/saphira-memoryd
	# Build commands follow the source layout once the repository
	# has content; they are completed at release, not invented here.
	echo "saphira-memoryd source cloned; build steps pending source content" >&2
	return 1
}

recipe_install()
{
	# Install steps follow the built source layout once the
	# repository has content; completed at release, not here.
	echo "saphira-memoryd install steps pending source content" >&2
	return 1
}

#!/bin/sh
pkgname=saphira-base-abi
pkgver=0.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira base ABI marker (Genesis transition; shrink-to-nothing target)'
license='MIT'
origin=saphira-base-abi
repo=saphira
url=https://saphira.vm2.uk/
# Genesis lineage: this marker descends from akadata-base-abi (v0.1,
# immutable-stage3-bootstrap). It exists only to anchor the generation-
# zero ABI during the transition; the end state is its removal, with
# musl, saphira-kernel-headers, gcc-libs and binutils as the real base packages.

recipe_build()
{
	:
}

recipe_install()
{
	install -d "$PKGDEST/usr/share/saphira"
	cat > "$PKGDEST/usr/share/saphira/base-abi" <<'EOF'
name=saphira-base-abi
version=0.2
policy=immutable-stage3-bootstrap
lineage=akadata-base-abi-0.1
EOF
}

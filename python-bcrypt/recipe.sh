#!/bin/sh

# python-bcrypt: bcrypt 5.0.0
#
# Rust extension. Upstream publishes musllinux wheels; the pinned
# musllinux wheel for the target architecture is vendored as a bootstrap
# artifact, the same pattern the tree already uses for python-poetry-core
# and python-hatchling. Building from the Rust sdist would require cargo
# to fetch crates at build time, which Saphira forbids ("no downloading
# dependencies during the build"); the verified musllinux wheel is fully
# offline, preserves the compiled extension, and is ABI3 (cp38-abi3) so it
# serves Python 3.14. A from-source Rust build with vendored crates is a
# deliberate future option, not a silent omission.

pkgname=python-bcrypt
pkgver=5.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="bcrypt: password hashing (Rust extension, musllinux wheel)"
license="Apache-2.0"
origin=bcrypt
repo=saphira
url=https://pypi.org/project/bcrypt/

case "${SAPHIRA_ARCH:-x86_64}" in
x86_64)
	bcrypt_wheel=bcrypt-5.0.0-cp38-abi3-musllinux_1_2_x86_64.whl
	bcrypt_sha256=3cf67a804fc66fc217e6914a5635000259fbbbb12e78a99488e4d5ba445a71eb
	;;
aarch64)
	bcrypt_wheel=bcrypt-5.0.0-cp38-abi3-musllinux_1_2_aarch64.whl
	bcrypt_sha256=801cad5ccb6b87d1b430f183269b94c24f248dddbbc5c1f78b6ed231743e001c
	;;
*)
	printf 'python-bcrypt: unsupported architecture: %s\n' "${SAPHIRA_ARCH:-x86_64}" >&2
	exit 1
	;;
esac

depends="python3"
makedepends="
    python3
    python3-pip
"

recipe_build()
{
	# The vendored musllinux wheel is the seed artifact: verify its bytes.
	echo "$bcrypt_sha256  $RECIPE_DIR/files/$bcrypt_wheel" | sha256sum -c -
}

recipe_install()
{
	python3 -m pip install \
		--no-index \
		--no-deps \
		--ignore-installed \
		--no-build-isolation \
		--no-compile \
		--no-cache-dir \
		--root "$PKGDEST" \
		--prefix /usr \
		"$RECIPE_DIR/files/$bcrypt_wheel"
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/bcrypt/_bcrypt*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-bcrypt staged payload is missing the compiled extension (bcrypt._bcrypt)" >&2
        return 1
    }
}

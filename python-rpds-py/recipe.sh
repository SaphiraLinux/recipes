#!/bin/sh

# python-rpds-py: rpds-py 2026.6.3
#
# Rust extension (persistent data structures for jsonschema). Upstream
# publishes musllinux wheels; the pinned musllinux wheel for the target
# architecture is vendored as a bootstrap artifact, the same pattern used
# for python-bcrypt/poetry-core/hatchling. Building the Rust sdist would
# require cargo to fetch crates at build time, which Saphira forbids; the
# verified musllinux wheel is offline and preserves the compiled
# extension. The wheel is CPython 3.14-specific (cp314), matching
# Saphira's python3 3.14. A from-source Rust build with vendored crates is
# a deliberate future option.

pkgname=python-rpds-py
pkgver=2026.6.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="rpds-py: Python bindings to Rust persistent data structures (jsonschema)"
license="MIT"
origin=rpds-py
repo=saphira
url=https://pypi.org/project/rpds-py/

case "${SAPHIRA_ARCH:-x86_64}" in
x86_64)
	rpds_wheel=rpds_py-2026.6.3-cp314-cp314-musllinux_1_2_x86_64.whl
	rpds_sha256=639c8929aa0afe81be836b04de888460d6bed38b9c54cfc18da8f6bfabf5af5d
	;;
aarch64)
	rpds_wheel=rpds_py-2026.6.3-cp314-cp314-musllinux_1_2_aarch64.whl
	rpds_sha256=4470ce197d4090875cf6affbf1f853338387428df97c4fb7b7106317b8214698
	;;
*)
	printf 'python-rpds-py: unsupported architecture: %s\n' "${SAPHIRA_ARCH:-x86_64}" >&2
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
	echo "$rpds_sha256  $RECIPE_DIR/files/$rpds_wheel" | sha256sum -c -
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
		"$RECIPE_DIR/files/$rpds_wheel"
    so=$(ls "$PKGDEST"/usr/lib/python3.14/site-packages/rpds/*.so \
        2>/dev/null | head -1)
    [ -n "$so" ] || {
        echo "ERROR: python-rpds-py staged payload is missing the compiled extension (rpds.*)" >&2
        return 1
    }
}

#!/bin/sh

# python-lxc: upstream Python bindings for liblxc, separate tarball.
# Never merged into lxc (core must not depend on Python); this may
# depend on lxc and its shared library.

pkgname=python-lxc
pkgver=7.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Python bindings for LXC (liblxc API)"
license="LGPL-2.1-or-later"
origin=python-lxc
repo=saphira
url=https://linuxcontainers.org/lxc/
# GPG-verified like lxc (same signer key -- see lxc/recipe.sh).
source=https://linuxcontainers.org/downloads/lxc/python3-lxc-7.0.0.tar.gz
sha256=f4da1fb5a89624a1fdac6769c87290572c0c88461f2f8080dcc3710ef44131ee

# lxc carries the runtime liblxc.so.1; lxc-dev is build-time only
# (headers + lxc.pc resolved via pkg-config by setup.py).
depends="
    lxc
    python3
"

makedepends="
    gcc
    lxc-dev
    pkgconf
    python3
    python3-dev
    python3-pip
    setuptools
    wheel
"

recipe_build()
{
	:
}

recipe_install()
{
	python3 -m pip install \
		--no-deps \
		--no-build-isolation \
		--no-compile \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/python-lxc/COPYING"
	# Import smoke test against the staging root: proves the C
	# extension links the freshly built liblxc. Fails closed.
	LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
	PYTHONPATH="$(echo "$PKGDEST"/usr/lib/python3*/site-packages)" \
		python3 -c "import _lxc; print(_lxc.__file__)" || {
		echo "ERROR: python-lxc extension failed to import" >&2
		return 1
	}
}

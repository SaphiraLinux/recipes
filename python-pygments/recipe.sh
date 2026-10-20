#!/bin/sh
pkgname=python-pygments
pkgver=2.21.0
pkgrel=1
pkgarch=noarch
pkgdesc='Syntax highlighting library (Python module, system package)'
license='BSD-2-Clause'
origin=python-pygments
repo=saphira
url=https://pypi.org/project/Pygments/
source=https://files.pythonhosted.org/packages/49/2e/ced460408999b33da6b31b0021b0f37d329e202d4169aeb164493778f25b/pygments-2.21.0.tar.gz
sha256=610ca751c9bc2492b38eb9a38a7fbc93edbbb2d7182edaf34e66ae493dee5c8c

depends="python3"

makedepends="
	python3
	python3-pip
	python-hatchling
"

recipe_build()
{
	:
}

recipe_install()
{
	PYTHONPATH="$SRC:/usr/lib/python3.14/site-packages" \
		python3 -m pip install \
		--no-index \
		--no-deps \
		--ignore-installed \
		--no-build-isolation \
		--no-compile \
		--no-cache-dir \
		--root "$PKGDEST" \
		--prefix /usr \
		"$SRC"
	# Smoke test (hermetic, no network): the install must have
	# recorded importable dist metadata. Full pytest suites need
	# pytest plus network fixtures, which the isolated builder
	# does not provide - documented, not silently skipped.
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('Pygments'))"
}

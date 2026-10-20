#!/bin/sh
pkgname=python-babel
pkgver=2.18.0
pkgrel=2
pkgarch=noarch
pkgdesc='Internationalization utilities (Python module, system package)'
license='BSD-3-Clause'
origin=python-babel
repo=saphira
url=https://pypi.org/project/Babel/
source=https://files.pythonhosted.org/packages/7d/b2/51899539b6ceeeb420d40ed3cd4b7a40519404f9baf3d4ac99dc413a834b/babel-2.18.0.tar.gz
sha256=b80b99a14bd085fcacfa15c9165f651fbb3406e66cc603abf11c5750937c992d

depends="python3"

makedepends="
	python3
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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('Babel'))"
}

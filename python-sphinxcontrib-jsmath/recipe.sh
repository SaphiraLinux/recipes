#!/bin/sh
pkgname=python-sphinxcontrib-jsmath
pkgver=1.0.1
pkgrel=2
pkgarch=noarch
pkgdesc='Sphinx JSMath renderer (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-jsmath
repo=saphira
url=https://pypi.org/project/sphinxcontrib-jsmath/
source=https://files.pythonhosted.org/packages/b2/e8/9ed3830aeed71f17c026a07a5097edcf44b692850ef215b161b8ad875729/sphinxcontrib-jsmath-1.0.1.tar.gz
sha256=a9925e4a4587247ed2191a22df5f6970656cb8ca2bd6284309578f2153e0c4b8

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-jsmath'))"
}

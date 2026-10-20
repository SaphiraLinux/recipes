#!/bin/sh
pkgname=python-sphinxcontrib-jquery
pkgver=4.1
pkgrel=1
pkgarch=noarch
pkgdesc='Sphinx jQuery static assets (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-jquery
repo=saphira
url=https://pypi.org/project/sphinxcontrib-jquery/
source=https://files.pythonhosted.org/packages/de/f3/aa67467e051df70a6330fe7770894b3e4f09436dea6881ae0b4f3d87cad8/sphinxcontrib-jquery-4.1.tar.gz
sha256=1620739f04e36a2c779f1a131a2dfd49b2fd07351bf1968ced074365933abc7a

depends="python3 python-sphinx"

makedepends="
	python3
	python3-pip
	python-flit-core
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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-jquery'))"
}

#!/bin/sh
pkgname=python-sphinxcontrib-qthelp
pkgver=2.0.0
pkgrel=2
pkgarch=noarch
pkgdesc='Sphinx Qt Help builder (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-qthelp
repo=saphira
url=https://pypi.org/project/sphinxcontrib-qthelp/
source=https://files.pythonhosted.org/packages/68/bc/9104308fc285eb3e0b31b67688235db556cd5b0ef31d96f30e45f2e51cae/sphinxcontrib_qthelp-2.0.0.tar.gz
sha256=4fe7d0ac8fc171045be623aba3e2a8f613f8682731f9153bb2e40ece16b9bbab

depends="python3"

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-qthelp'))"
}

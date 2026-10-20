#!/bin/sh
pkgname=python-sphinxcontrib-applehelp
pkgver=2.0.0
pkgrel=2
pkgarch=noarch
pkgdesc='Sphinx Apple Help builder (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-applehelp
repo=saphira
url=https://pypi.org/project/sphinxcontrib-applehelp/
source=https://files.pythonhosted.org/packages/ba/6e/b837e84a1a704953c62ef8776d45c3e8d759876b4a84fe14eba2859106fe/sphinxcontrib_applehelp-2.0.0.tar.gz
sha256=2f29ef331735ce958efa4734873f084941970894c6090408b079c61b2e1c06d1

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-applehelp'))"
}

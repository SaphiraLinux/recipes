#!/bin/sh
pkgname=python-docutils
pkgver=0.22.1
pkgrel=2
pkgarch=noarch
pkgdesc='ReStructuredText processor (Python module, system package)'
license='BSD-2-Clause'
origin=python-docutils
repo=saphira
url=https://pypi.org/project/docutils/
source=https://files.pythonhosted.org/packages/e4/47/d869000fb74438584858acc628a364b277fc012695f0dfd513cb10f99768/docutils-0.22.1.tar.gz
sha256=d2fb50923a313532b6d41a77776d24cb459a594be9b7e4afa1fbcb5bda1893e6

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('docutils'))"
}

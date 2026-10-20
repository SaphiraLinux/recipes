#!/bin/sh
pkgname=python-sphinxcontrib-devhelp
pkgver=2.0.0
pkgrel=2
pkgarch=noarch
pkgdesc='Sphinx Devhelp builder (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-devhelp
repo=saphira
url=https://pypi.org/project/sphinxcontrib-devhelp/
source=https://files.pythonhosted.org/packages/f6/d2/5beee64d3e4e747f316bae86b55943f51e82bb86ecd325883ef65741e7da/sphinxcontrib_devhelp-2.0.0.tar.gz
sha256=411f5d96d445d1d73bb5d52133377b4248ec79db5c793ce7dbe59e074b4dd1ad

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-devhelp'))"
}

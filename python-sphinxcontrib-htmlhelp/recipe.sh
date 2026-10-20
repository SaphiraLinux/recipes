#!/bin/sh
pkgname=python-sphinxcontrib-htmlhelp
pkgver=2.1.0
pkgrel=2
pkgarch=noarch
pkgdesc='Sphinx HTML Help builder (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-htmlhelp
repo=saphira
url=https://pypi.org/project/sphinxcontrib-htmlhelp/
source=https://files.pythonhosted.org/packages/43/93/983afd9aa001e5201eab16b5a444ed5b9b0a7a010541e0ddfbbfd0b2470c/sphinxcontrib_htmlhelp-2.1.0.tar.gz
sha256=c9e2916ace8aad64cc13a0d233ee22317f2b9025b9cf3295249fa985cc7082e9

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-htmlhelp'))"
}

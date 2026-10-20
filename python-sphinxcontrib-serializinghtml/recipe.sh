#!/bin/sh
pkgname=python-sphinxcontrib-serializinghtml
pkgver=2.0.0
pkgrel=2
pkgarch=noarch
pkgdesc='Sphinx serializing HTML builder (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinxcontrib-serializinghtml
repo=saphira
url=https://pypi.org/project/sphinxcontrib-serializinghtml/
source=https://files.pythonhosted.org/packages/3b/44/6716b257b0aa6bfd51a1b31665d1c205fb12cb5ad56de752dfa15657de2f/sphinxcontrib_serializinghtml-2.0.0.tar.gz
sha256=e9d912827f872c029017a53f0ef2180b327c3f7fd23c87229f7a8e8b70031d4d

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinxcontrib-serializinghtml'))"
}

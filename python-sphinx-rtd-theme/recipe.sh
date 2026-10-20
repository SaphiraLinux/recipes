#!/bin/sh
pkgname=python-sphinx-rtd-theme
pkgver=3.1.0
pkgrel=1
pkgarch=noarch
pkgdesc='Read the Docs theme for Sphinx (Python module, system package)'
license='MIT'
origin=python-sphinx-rtd-theme
repo=saphira
url=https://pypi.org/project/sphinx-rtd-theme/
source=https://files.pythonhosted.org/packages/84/68/a1bfbf38c0f7bccc9b10bbf76b94606f64acb1552ae394f0b8285bfaea25/sphinx_rtd_theme-3.1.0.tar.gz
sha256=b44276f2c276e909239a4f6c955aa667aaafeb78597923b1c60babc76db78e4c

depends="python3 python-sphinx python-docutils python-sphinxcontrib-jquery"

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('sphinx-rtd-theme'))"
}

#!/bin/sh
pkgname=python-sphinx
pkgver=9.1.0
pkgrel=1
pkgarch=noarch
pkgdesc='Python documentation generator (Python module, system package)'
license='BSD-2-Clause'
origin=python-sphinx
repo=saphira
url=https://pypi.org/project/Sphinx/
source=https://files.pythonhosted.org/packages/cd/bd/f08eb0f4eed5c83f1ba2a3bd18f7745a2b1525fad70660a1c00224ec468a/sphinx-9.1.0.tar.gz
sha256=7741722357dd75f8190766926071fed3bdc211c74dd2d7d4df5404da95930ddb

depends="python3 python-babel python-docutils python-jinja2 python-pygments python-snowballstemmer python-alabaster python-imagesize python-requests python-roman-numerals packaging python-sphinxcontrib-applehelp python-sphinxcontrib-devhelp python-sphinxcontrib-htmlhelp python-sphinxcontrib-jsmath python-sphinxcontrib-qthelp python-sphinxcontrib-serializinghtml"

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('Sphinx'))"
}

#!/bin/sh
pkgname=python-roman-numerals
pkgver=4.1.0
pkgrel=2
pkgarch=noarch
pkgdesc='Roman numeral conversion (Python module, system package)'
license='0BSD OR CC0-1.0'
origin=python-roman-numerals
repo=saphira
url=https://pypi.org/project/roman-numerals/
source=https://files.pythonhosted.org/packages/ae/f9/41dc953bbeb056c17d5f7a519f50fdf010bd0553be2d630bc69d1e022703/roman_numerals-4.1.0.tar.gz
sha256=1af8b147eb1405d5839e78aeb93131690495fe9da5c91856cb33ad55a7f1e5b2

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('roman-numerals'))"
}

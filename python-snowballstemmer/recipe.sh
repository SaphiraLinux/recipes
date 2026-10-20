#!/bin/sh
pkgname=python-snowballstemmer
pkgver=3.1.1
pkgrel=2
pkgarch=noarch
pkgdesc='Snowball stemming library (Python module, system package)'
license='BSD-3-Clause'
origin=python-snowballstemmer
repo=saphira
url=https://pypi.org/project/snowballstemmer/
source=https://files.pythonhosted.org/packages/43/f8/0a71edf031f03c40db17503cb8ca78a69a171254e568e7db241b0ab57ea1/snowballstemmer-3.1.1.tar.gz
sha256=e07bbc54a0d798fe6010a12398422e62a8bfbba95c394fd0956ef58cb4d3e260

depends="python3"

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('snowballstemmer'))"
}

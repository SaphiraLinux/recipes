#!/bin/sh
pkgname=python-imagesize
pkgver=2.0.1
pkgrel=2
pkgarch=noarch
pkgdesc='Image dimension reader (Python module, system package)'
license='MIT'
origin=python-imagesize
repo=saphira
url=https://pypi.org/project/imagesize/
source=https://files.pythonhosted.org/packages/fb/5e/513ff06670c84e7b9887c1fdf61b2d42b4f574a831f2f1d2222023049d8a/imagesize-2.0.1.tar.gz
sha256=b2ba6a4dea487a7ebcd53248d3476aca449d30db12a2dde5e0c5ca9624fd77e5

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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('imagesize'))"
}

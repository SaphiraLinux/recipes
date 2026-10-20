#!/bin/sh
pkgname=python-hawkmoth
pkgver=0.22.0
pkgrel=1
pkgarch=noarch
pkgdesc='Hawkmoth Sphinx C autodoc (Python module, mesa docs extension)'
license='BSD-2-Clause'
origin=python-hawkmoth
repo=saphira
url=https://pypi.org/project/hawkmoth/
source=https://files.pythonhosted.org/packages/1c/50/fa6009e1edbf341aa25d86d9527063f851a8ce3f19250aa355c2d49cb1da/hawkmoth-0.22.0.tar.gz
sha256=bb65c16da7857ee5ec2f2bf3dd05626dc040b44b4662615afab6323769159f10

depends="python3 python-sphinx"
makedepends="
	python3
	python3-pip
	python-hatchling
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
	PYTHONPATH="$PKGDEST/usr/lib/python3.14/site-packages" python3 -c "import importlib.metadata as m; print(m.version('hawkmoth'))"
}

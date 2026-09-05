#!/bin/sh

pkgname=pyparsing
pkgver=3.3.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python parsing class library (system package, no venv)'
license='MIT'
origin=pyparsing
repo=saphira
url=https://pypi.org/project/pyparsing/
# Vendored PyPI wheel; stdlib extraction, no pip.
pyparsing_sha256=850ba148bd908d7e2411587e247a1e4f0327839c40e2e5e6d05a007ecc69911d

replaces="python-pyparsing"
depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/pyparsing-3.3.2-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
import sys, zipfile, pathlib, subprocess
wheel, pkgdest = sys.argv[1], sys.argv[2]
site = subprocess.run(["python3", "-c", "import sysconfig; print(sysconfig.get_path('purelib', vars={'base': '/usr'}))"], capture_output=True, text=True, check=True).stdout.strip()
target = pathlib.Path(pkgdest) / site.lstrip('/')
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(wheel) as z:
    z.extractall(target)
print("installed wheel to", target)
PYINSTALL
}

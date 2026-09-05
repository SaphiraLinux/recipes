#!/bin/sh

pkgname=certifi
pkgver=2026.7.22
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python certifi module (system package, no venv)'
license='Apache-2.0'
origin=certifi
repo=saphira
url=https://pypi.org/project/certifi/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
certifi_sha256=62f22742b58a1a33014a2b6b706588a8d7e2a88ae7bd1a6ebe8c992928483775

replaces="python-certifi"
depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/certifi-2026.7.22-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
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

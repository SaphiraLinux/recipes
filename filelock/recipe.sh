#!/bin/sh

pkgname=filelock
pkgver=3.32.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python filelock module (system package, no venv)'
license='Apache-2.0'
origin=filelock
repo=saphira
url=https://pypi.org/project/filelock/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
filelock_sha256=22e58ca3b1ae3b98993b762d7338367ae64fe50252bf78d59da3bfebcdf1cedd

depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/filelock-3.32.4-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
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

#!/bin/sh

pkgname=fsspec
pkgver=2026.7.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python fsspec module (system package, no venv)'
license='Apache-2.0'
origin=fsspec
repo=saphira
url=https://pypi.org/project/fsspec/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
fsspec_sha256=b57ddbafedfaef7018c1ecab32aa200a9d7ca26b77965f64e48b70061249d279

depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/fsspec-2026.7.0-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
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

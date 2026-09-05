#!/bin/sh

pkgname=httpx
pkgver=0.28.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python httpx module (system package, no venv)'
license='Apache-2.0'
origin=httpx
repo=saphira
url=https://pypi.org/project/httpx/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
httpx_sha256=d909fcccc110f8c7faf814ca82a9a4d816bc5a6dbfea25d6591d6985b8ba59ad

depends="anyio certifi httpcore idna"
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/httpx-0.28.1-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
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

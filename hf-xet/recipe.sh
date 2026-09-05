#!/bin/sh

pkgname=hf-xet
pkgver=1.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python hf-xet module (system package, no venv)'
license='Apache-2.0'
origin=hf-xet
repo=saphira
url=https://pypi.org/project/hf-xet/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
hf_xet_sha256=8fb4f71cba6129110c3374a33f919001ff130488fc23553698e34cc1c2a1198c

depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/hf_xet-1.6.0-cp38-abi3-musllinux_1_2_x86_64.whl" "$PKGDEST" <<'PYINSTALL'
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

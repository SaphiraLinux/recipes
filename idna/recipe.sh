#!/bin/sh

pkgname=idna
pkgver=3.19
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python idna module (system package, no venv)'
license='Apache-2.0'
origin=idna
repo=saphira
url=https://pypi.org/project/idna/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
idna_sha256=815e7be7a7806d54abb586dc943addc79e8b2ee16915059658cbeff4b1b43bf4

replaces="python-idna"
depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/idna-3.19-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
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

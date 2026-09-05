#!/bin/sh

pkgname=anyio
pkgver=4.14.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python anyio module (system package, no venv)'
license='Apache-2.0'
origin=anyio
repo=saphira
url=https://pypi.org/project/anyio/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
anyio_sha256=9f505dda5ac9f0c8309b5e8bd445a8c2bf7246f3ce950121e45ea15bc41d1494

depends="idna typing-extensions"
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/anyio-4.14.2-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
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

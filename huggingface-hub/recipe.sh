#!/bin/sh

pkgname=huggingface-hub
pkgver=1.29.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python huggingface-hub module (system package, no venv)'
license='Apache-2.0'
origin=huggingface-hub
repo=saphira
url=https://pypi.org/project/huggingface-hub/
# Vendored PyPI wheel: upstream musllinux builds for binary wheels
# (hf-xet is Rust; pyyaml is cp314 musllinux); pure-python otherwise.
# Stdlib wheel extraction; dependencies are explicit Saphira packages.
huggingface_hub_sha256=b00f7782afc14db4bc6572763810a635bdfbab8623d957bfb553bd18e03852cd

depends="click filelock fsspec hf-xet httpx packaging pyyaml tqdm typing-extensions"
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	python3 - "$RECIPE_DIR/files/huggingface_hub-1.29.0-py3-none-any.whl" "$PKGDEST" <<'PYINSTALL'
import sys, zipfile, pathlib
wheel, pkgdest = sys.argv[1], sys.argv[2]
import subprocess
site = subprocess.run(["python3", "-c", "import sysconfig; print(sysconfig.get_path('purelib', vars={'base': '/usr'}))"], capture_output=True, text=True, check=True).stdout.strip()
target = pathlib.Path(pkgdest) / site.lstrip('/')
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(wheel) as z:
    z.extractall(target)
print("installed wheel to", target)
PYINSTALL
	install -d "$PKGDEST/usr/bin"
	cat > "$PKGDEST/usr/bin/hf" <<'EOF'
#!/usr/bin/python3
import sys
from huggingface_hub.cli.hf import main
sys.exit(main())
EOF
	cat > "$PKGDEST/usr/bin/huggingface-cli" <<'EOF'
#!/usr/bin/python3
import sys
from huggingface_hub.cli.deprecated_cli import main
sys.exit(main())
EOF
	chmod 0755 "$PKGDEST/usr/bin/hf" "$PKGDEST/usr/bin/huggingface-cli"
}

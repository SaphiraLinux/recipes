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
# Vendored PyPI wheel; stdlib extraction, no pip. vendor=+sha256= is the
# fetch contract: when the wheel is absent from files/, the builder
# downloads vendor=, verifies sha256, and exposes it as $SOURCE_ARCHIVE
# (wheels are consumed as files, not extracted sources, so this recipe
# reads $SOURCE_ARCHIVE rather than $SRC on the fetch path).
vendor=https://files.pythonhosted.org/packages/10/bd/c038d7cc38edc1aa5bf91ab8068b63d4308c66c4c8bb3cbba7dfbc049f9c/pyparsing-3.3.2-py3-none-any.whl
sha256=850ba148bd908d7e2411587e247a1e4f0327839c40e2e5e6d05a007ecc69911d

replaces="python-pyparsing"
depends=""
makedepends="python3"

recipe_build()
{
	:
}

recipe_install()
{
	# Local wheel wins when present (verified, never re-downloaded);
	# otherwise install from the builder-verified $SOURCE_ARCHIVE.
	WHEEL="$RECIPE_DIR/files/pyparsing-3.3.2-py3-none-any.whl"
	if [ -f "$WHEEL" ]; then
		echo "$sha256  $WHEEL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local pyparsing wheel and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		WHEEL=$SOURCE_ARCHIVE
	fi
	python3 - "$WHEEL" "$PKGDEST" <<'PYINSTALL'
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

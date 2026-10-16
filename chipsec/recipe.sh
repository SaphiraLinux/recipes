#!/bin/sh
pkgname=chipsec
pkgver=2.0.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Platform security assessment framework (research systems only, NOT for production use)'
license='GPL-2.0-only'
origin=chipsec
repo=saphira
url=https://github.com/chipsec/chipsec
# Pinned release tag 2.0.9 (chipsec2 line). Deliberately a separate
# package, never a dependency of firmware-tools: upstream warns this is
# for test systems only (low-level hardware access, needs a kernel
# driver built against the running kernel - see drivers/linux, shipped
# as source for manual target builds, NOT built here).
source=https://github.com/chipsec/chipsec/archive/refs/tags/2.0.9.tar.gz
sha256=53671021de83e8c6952f7b4bb1d05c004ae53e13c2da72c30a53a1f26395a832

depends="python3 python-distro"
# --skip-driver equivalent: the kernel module needs the RUNNING kernel's
# build tree (/lib/modules/$(uname -r)/build), which does not exist in
# the isolated build namespace. Driver sources ship under
# /usr/src/chipsec-driver for deliberate on-target builds. Pure-Python
# install needs only the interpreter at build time.
makedepends="python3"

recipe_build() {
	# Tag tarball vendored under URL basename (libconfuse precedent).
	CHIPSEC_BALL="$RECIPE_DIR/files/${pkgver}.tar.gz"
	echo "$sha256  $CHIPSEC_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$CHIPSEC_BALL"
	python3 -m py_compile "$SRC/chipsec_main.py" "$SRC/chipsec_util.py"
}

recipe_install() {
	# setup.py build unconditionally probes a C compiler (even with
	# --skip-driver). This is a pure-Python tree, so install it directly
	# into site-packages (packaging-recipe precedent) instead.
	python3 - "$SRC" "$PKGDEST" <<'PYINSTALL'
import sys, shutil, pathlib, subprocess
src, pkgdest = sys.argv[1], sys.argv[2]
site = subprocess.run(["python3", "-c", "import sysconfig; print(sysconfig.get_path('purelib', vars={'base': '/usr'}))"], capture_output=True, text=True, check=True).stdout.strip()
target = pathlib.Path(pkgdest) / site.lstrip('/')
target.mkdir(parents=True, exist_ok=True)
for tree in ("chipsec", "chipsec_tools"):
    shutil.copytree(f"{src}/{tree}", target / tree,
                    ignore=shutil.ignore_patterns("__pycache__"))
print("installed python tree to", target)
PYINSTALL
	for script in chipsec_main.py chipsec_util.py; do
		install -D -m 0755 "$SRC/$script" "$PKGDEST/usr/bin/$script"
	done
	install -D -m 0644 "$SRC/drivers/linux/WARNING.txt" \
		"$PKGDEST/usr/share/doc/chipsec/WARNING.txt"
	install -D -m 0644 "$SRC/chipsec-manual.pdf" \
		"$PKGDEST/usr/share/doc/chipsec/chipsec-manual.pdf"
	# Driver sources for deliberate on-target builds (needs the
	# running kernel's build tree; never built in the sandbox).
	mkdir -p "$PKGDEST/usr/src/chipsec-driver"
	cp -a "$SRC/drivers/linux/." "$PKGDEST/usr/src/chipsec-driver/"
	chmod -R u+w "$PKGDEST/usr/src/chipsec-driver"
}

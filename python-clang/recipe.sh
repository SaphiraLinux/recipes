#!/bin/sh

pkgname=python-clang
pkgver=22.1.8
pkgrel=1
pkgarch=noarch
pkgdesc="Clang Python bindings (libclang cindex; mesa hawkmoth docs requirement)"
license="Apache-2.0 WITH LLVM-exception"
origin=python-clang
repo=saphira
url=https://github.com/llvm/llvm-project
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    python3
    clang
"

makedepends="
    python3
    python3-pip
    setuptools
    wheel
"

# Pure-python bindings shipped in the LLVM tree
# (clang/bindings/python). Version-locked to the native LLVM:
# hawkmoth imports clang.cindex at mesa doc build time, and the
# bindings must match the libclang they drive. Third vendoring of
# the llvm-project archive in the tree (llvm, clang recipes carry
# it too): the single-source contract gives each recipe its own
# archive, and only these two files are consumed.
recipe_build()
{
	:
}

recipe_install()
{
	pylib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')
	case $pylib in
		/usr/lib/python3*/site-packages) ;;
		*) echo "ERROR: unexpected python purelib: $pylib" >&2; return 1 ;;
	esac
	install -d -m 0755 "$PKGDEST$pylib/clang"
	install -m 0644 "$SRC/clang/bindings/python/clang/__init__.py" \
		"$PKGDEST$pylib/clang/__init__.py"
	install -m 0644 "$SRC/clang/bindings/python/clang/cindex.py" \
		"$PKGDEST$pylib/clang/cindex.py"
	python3 -c "import ast
for f in [\"$PKGDEST$pylib/clang/__init__.py\", \"$PKGDEST$pylib/clang/cindex.py\"]:
    ast.parse(open(f).read())" || {
		echo "ERROR: python-clang payload files do not parse" >&2
		return 1
	}
}

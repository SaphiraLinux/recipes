#!/bin/sh

pkgname=lld
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLVM linker: ld.lld, ld64.lld, lld-link and wasm-ld"
license="Apache-2.0 WITH LLVM-exception"
origin=lld
repo=saphira
url=https://lld.llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    llvm>=22.1.8-r1
"

makedepends="
    binutils
    cmake
    gcc
    llvm>=22.1.8-r1
    ninja
    python3
    zlib-dev
    zstd-dev
    libxml2-dev
"

# Proven v0 flags: standalone lld build against the installed LLVM,
# tests off, lld installed as /usr/bin/lld with alias symlinks; it must
# never take over /usr/bin/ld.
recipe_build()
{
	cmake -G Ninja "$SRC/lld" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_DIR=/usr/lib/cmake/llvm -DLLVM_INCLUDE_TESTS=OFF \
		-DLLD_INCLUDE_TESTS=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	bin=$PKGDEST/usr/bin
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	test -f "$bin/lld" && test ! -L "$bin/lld" && test -x "$bin/lld" ||
		{ printf 'lld: LLD executable is missing or is not a regular executable\n' >&2; exit 1; }
	for alias in ld.lld ld64.lld lld-link wasm-ld; do
		rm -f -- "$bin/$alias"
		ln -s lld "$bin/$alias"
	done
	for alias in ld.lld ld64.lld lld-link wasm-ld; do
		test -L "$bin/$alias" ||
			{ printf 'lld: LLD alias is not a symlink: %s\n' "$alias" >&2; exit 1; }
		test "$(readlink "$bin/$alias")" = lld ||
			{ printf 'lld: LLD alias has the wrong target: %s\n' "$alias" >&2; exit 1; }
	done
	test ! -e "$bin/ld" && test ! -L "$bin/ld" ||
		{ printf 'lld: LLD must not replace /usr/bin/ld\n' >&2; exit 1; }
	install -D -m 0644 "$SRC/lld/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/lld/LICENSE.TXT"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'lld: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

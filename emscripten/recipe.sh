#!/bin/sh

pkgname=emscripten
pkgver=6.0.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Emscripten: C/C++ to WebAssembly compiler toolchain"
license="MIT"
origin=emscripten
repo=saphira
url=https://emscripten.org/
# GitHub tag archive; npm dependencies are fetched per-package and
# verified against npm.lock (pinned URL + sha256), matching the proven
# v0 offline-ports build.
source=https://github.com/emscripten-core/emscripten/archive/refs/tags/6.0.5.tar.gz
sha256=2a40823fec2ce3c6f85f6562a2cd9aa09b468542a2aa769e50682185ce1d9350

depends="
    binaryen>=131-r1
    clang-wasm>=22.1.8-r1
    lld>=22.1.8-r1
    llvm-wasm>=22.1.8-r1
    nodejs>=24.18.1-r1
"

makedepends="
    binaryen>=131-r1
    clang-wasm>=22.1.8-r1
    curl
    lld>=22.1.8-r1
    llvm-wasm>=22.1.8-r1
    nodejs>=24.18.1-r1
    python3
"

fatal()
{
	printf 'emscripten: %s\n' "$1" >&2
	exit 1
}

emscripten_commands()
{
	printf '%s\n' emcc em++ emar embuilder emcmake emconfigure emmake \
		emranlib emrun emscan-deps emsize emstrip
}

prepare_emscripten_launchers()
{
	local command
	while IFS= read -r command; do
		test -f "$SRC/$command.py" ||
			fatal "missing Emscripten launcher source: $command.py"
		chmod 0755 "$SRC/$command.py"
		sed -i '1c#!/usr/bin/python3' "$SRC/$command.py"
		ln -sfn "$command.py" "$SRC/$command"
	done <<EOF
$(emscripten_commands)
EOF
}

recipe_build()
{
	patch -d "$SRC" -p1 \
		< "$RECIPE_DIR/offline-ports.patch"
	patch -d "$SRC" -p1 \
		< "$RECIPE_DIR/deterministic-macro-paths.patch"
	while IFS='|' read -r destination version url checksum archive license; do
		path=$BUILDDIR/$archive
		curl -fsSL --retry 3 --output "$path" "$url" ||
			fatal "failed to download locked npm archive: $archive"
		printf '%s  %s\n' "$checksum" "$path" | sha256sum -c - ||
			fatal "locked npm archive checksum mismatch: $archive"
		mkdir -p "$SRC/$destination"
		tar --no-same-owner -xf "$path" --strip-components=1 -C "$SRC/$destination"
	done < "$RECIPE_DIR/npm.lock"
	prepare_emscripten_launchers
	cat > "$SRC/.emscripten" <<EOF
LLVM_ROOT = '/usr/lib/emscripten-toolchain/bin'
BINARYEN_ROOT = '/usr/lib/emscripten-toolchain'
NODE_JS = ['/usr/bin/node']
CACHE = '/usr/lib/emscripten/cache'
PORTS = '/var/cache/emscripten/ports'
EOF
	cat > "$BUILDDIR/emscripten.conf" <<EOF
LLVM_ROOT = '/usr/lib/emscripten-toolchain/bin'
BINARYEN_ROOT = '/usr/lib/emscripten-toolchain'
NODE_JS = ['/usr/bin/node']
CACHE = '$BUILDDIR/cache'
PORTS = '$BUILDDIR/ports'
EOF
	cd "$SRC"
	EM_CONFIG="$BUILDDIR/emscripten.conf" EM_CACHE="$BUILDDIR/cache" \
		EM_PORTS="$BUILDDIR/ports" EMCC_CORES="${JOBS:-$(nproc)}" \
		python3 -c '
import sys
import embuilder
sys.argv = ["embuilder.py", "build", *[target for target in embuilder.MINIMAL_TASKS if target not in embuilder.PORTS]]
raise SystemExit(embuilder.main())
'
}

recipe_install()
{
	destination=$PKGDEST/usr/lib/emscripten
	install -d -m 0755 "$destination" "$PKGDEST/usr/bin"
	cp -a "$SRC/." "$destination/"
	rm -rf "$destination/test" "$destination/.circleci" \
		"$destination/.github"
	cp -a "$BUILDDIR/cache" "$destination/cache"
	while IFS= read -r command; do
		ln -sfn "../lib/emscripten/$command.py" \
			"$PKGDEST/usr/bin/$command"
	done <<EOF
$(emscripten_commands)
EOF
	EM_CONFIG="$destination/.emscripten" \
		python3 "$destination/emcc.py" --version ||
		fatal "staged emcc --version failed"
	if matches=$(grep -R -a -l -F "$BUILDDIR" "$destination/cache"; grep -R -a -l -F "$SRC" "$destination/cache"); then
		printf 'emscripten: Emscripten system cache contains build paths:\n' >&2
		printf '  %s\n' $matches >&2
		fatal "Emscripten system cache contains build paths"
	fi
}

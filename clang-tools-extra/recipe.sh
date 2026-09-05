#!/bin/sh

pkgname=clang-tools-extra
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Clang extra tools: clang-tidy, clangd and related tooling"
license="Apache-2.0 WITH LLVM-exception"
origin=clang-tools-extra
repo=saphira
url=https://clang.llvm.org/extra/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    clang>=22.1.8-r1
    llvm>=22.1.8-r1
"

makedepends="
    binutils
    clang>=22.1.8-r1
    cmake
    gcc
    llvm>=22.1.8-r1
    ninja
    python3
    zlib-dev
    zstd-dev
    libxml2-dev
"

# Proven v0 flags: standalone superproject build against the installed
# LLVM and Clang cmake configs, tests/docs off, a fixed tool set built
# and verified, clang-format/diagtool/hmaptool excluded (owned by the
# clang package path).
recipe_build()
{
	project_dir=$BUILDDIR/clang-tools-extra-project
	mkdir -p "$project_dir"
	printf '%s\n' \
		'cmake_minimum_required(VERSION 3.20)' \
		'project(ClangToolsExtraStandalone C CXX)' \
		'find_package(Python3 COMPONENTS Interpreter REQUIRED)' \
		'find_package(LLVM 22.1.8 EXACT REQUIRED CONFIG PATHS /usr/lib/cmake/llvm NO_DEFAULT_PATH)' \
		'find_package(Clang 22.1.8 EXACT REQUIRED CONFIG PATHS /usr/lib/cmake/clang NO_DEFAULT_PATH)' \
		'list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}" "${CLANG_CMAKE_DIR}")' \
		'include(AddLLVM)' \
		'include(AddClang)' \
		'include(HandleLLVMOptions)' \
		'if(NOT TARGET ClangDriverOptions)' \
		'  add_custom_target(ClangDriverOptions)' \
		'endif()' \
		'if(NOT TARGET clang-resource-headers)' \
		'  add_custom_target(clang-resource-headers)' \
		'endif()' \
		'if(NOT TARGET ClangSACheckers)' \
		'  add_custom_target(ClangSACheckers)' \
		'endif()' \
		'include_directories("${CMAKE_BINARY_DIR}/clang-tools-extra/clang-tidy/misc")' \
		'add_subdirectory("${CLANG_TOOLS_EXTRA_SOURCE_DIR}" clang-tools-extra)' \
		> "$project_dir/CMakeLists.txt"
	cmake -G Ninja "$project_dir" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DCLANG_TOOLS_EXTRA_SOURCE_DIR="$SRC/clang-tools-extra" \
		-DLLVM_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_TESTS=OFF \
		-DCLANG_TOOLS_EXTRA_INCLUDE_DOCS=OFF
	ninja -C "$BUILDDIR" \
		clang-apply-replacements clang-change-namespace clang-doc \
		clang-include-fixer clang-move clang-query clang-reorder-fields \
		clang-tidy clang-tidy-confusable-chars-gen clangd find-all-symbols \
		modularize pp-trace
}

clang_tools_extra_expected_tools()
{
	printf '%s\n' \
		clang-apply-replacements clang-change-namespace clang-doc \
		clang-include-fixer clang-move clang-query clang-reorder-fields \
		clang-tidy clang-tidy-confusable-chars-gen clangd find-all-symbols \
		modularize pp-trace run-clang-tidy
}

recipe_install()
{
	install -d "$PKGDEST/usr/bin"
	for tool in $(clang_tools_extra_expected_tools); do
		rm -f "$PKGDEST/usr/bin/$tool"
	done
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" \
		install-clangApplyReplacements install-clangChangeNamespace \
		install-clangDoc install-clangIncludeFixer install-clangMove \
		install-clangQuery install-clangReorderFields install-clangTidy \
		install-clangdMain install-findAllSymbols
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR" \
		--component clang-tidy
	rm -f -- "$PKGDEST/usr/bin/clang-format" \
		"$PKGDEST/usr/bin/diagtool" \
		"$PKGDEST/usr/bin/hmaptool"
	missing_tools=
	for tool in $(clang_tools_extra_expected_tools); do
		tool_path=
		for tool_root in "$BUILDDIR/clang-tools-extra" "$SRC/clang-tools-extra"; do
			candidate=$(find "$tool_root" -type f -name "$tool" -perm -111 -print -quit 2>/dev/null)
			if test -n "$candidate"; then
				tool_path=$candidate
				break
			fi
		done
		if test -n "$tool_path"; then
			install -m 0755 "$tool_path" "$PKGDEST/usr/bin/$tool"
		elif test -x "$PKGDEST/usr/bin/$tool"; then
			:
		else
			missing_tools="$missing_tools
  $tool"
		fi
	done
	if test -n "$missing_tools"; then
		printf 'clang-tools-extra: missing Clang extra tools:%s\n' "$missing_tools" >&2
		exit 1
	fi
	missing_staged_tools=
	for tool in $(clang_tools_extra_expected_tools); do
		if ! test -x "$PKGDEST/usr/bin/$tool"; then
			missing_staged_tools="$missing_staged_tools
  $tool"
		fi
	done
	if test -n "$missing_staged_tools"; then
		printf 'clang-tools-extra: unstaged Clang extra tools:%s\n' "$missing_staged_tools" >&2
		exit 1
	fi
	for excluded in clang-format diagtool hmaptool; do
		test ! -e "$PKGDEST/usr/bin/$excluded" &&
			test ! -L "$PKGDEST/usr/bin/$excluded" ||
			{ printf 'clang-tools-extra: duplicates Clang path: %s\n' "$excluded" >&2; exit 1; }
	done
	install -D -m 0644 "$SRC/clang-tools-extra/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/clang-tools-extra/LICENSE.TXT"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'clang-tools-extra: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

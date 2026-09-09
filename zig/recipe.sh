#!/bin/sh

# Zig toolchain, bootstrapped from the official static stage0 binary
# (rustc bootstrap.lock pattern: pinned URL + sha256, verified before
# use). Upstream 0.16.x supports LLVM 21-22 per its release notes;
# repo LLVM is 22.1.8, inside the window. Flag confidence: --prefix,
# -Doptimize, -Dtarget and -Dversion-string are certain; the
# -Dsystem-* trio follows the zig-bootstrap convention and fails
# visibly (unknown -D is an error) if 0.16 renamed them.

pkgname=zig
pkgver=0.16.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Zig toolchain (stage0-bootstrapped, system LLVM)"
license="MIT"
origin=zig
repo=saphira
url=https://ziglang.org/
source=https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz
sha256=43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf

depends=""

makedepends="
    binutils
    clang
    curl
    gcc
    libclang
    lld
    llvm
    make
    python3
"

fatal()
{
	printf 'zig: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	stage0=$BUILDDIR/zig-stage0
	expected=$(awk -F'|' '$5 == "zig-x86_64-linux-0.16.0.tar.xz" { print $4; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$expected" || fatal "bootstrap archive is not locked"
	curl -fsSL --retry 3 --output "$BUILDDIR/stage0.tar.xz" \
		"https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz" ||
		fatal "failed to download bootstrap archive"
	printf '%s  %s\n' "$expected" "$BUILDDIR/stage0.tar.xz" | sha256sum -c - ||
		fatal "bootstrap archive checksum mismatch"
	mkdir -p "$stage0"
	tar -xf "$BUILDDIR/stage0.tar.xz" -C "$stage0" --strip-components=1
	test -x "$stage0/zig" || fatal "bootstrap archive has no zig binary"
	"$stage0/zig" version | grep -q "^0.16.0" || fatal "unexpected bootstrap version"
	cd "$SRC"
	"$stage0/zig" build --prefix "$BUILDDIR/zig-out" \
		-Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl \
		-Dversion-string=0.16.0 \
		-Dsystem-llvm=true -Dsystem-clang=true -Dsystem-lld=true
}

recipe_install()
{
	cp -a "$BUILDDIR/zig-out/." "$PKGDEST/"
	# Validate the staged compiler here, against the actual Saphira
	# musl it must run on (static stage0 ran anywhere; this proof is
	# Saphira-specific).
	test -x "$PKGDEST/usr/bin/zig"
	LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/zig" version | grep -q "^0.16.0"
	printf 'pub fn main() void {}\n' > "$BUILDDIR/stage0-hello.zig"
	LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/zig" run "$BUILDDIR/stage0-hello.zig"
}

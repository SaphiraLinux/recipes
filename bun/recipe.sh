#!/bin/sh

# Bun JavaScript runtime/bundler/package manager, built from source.
# The build is self-hosted (needs a Bun binary) and submodule-complete
# (JavaScriptCore et al. live in submodules the release tarball does
# not contain), so recipe_build clones --recursive at the pinned tag:
# the source= tarball stays as the pinned provenance record while the
# clone carries the exact submodule shas the tag records. Stage0 is
# the GPG-lineage upstream musl-baseline asset (bootstrap.lock pin),
# used ONLY as a build tool, never shipped.
# Saphira musl is not stock musl (enlarged default thread stack plus
# the in6 coordination patch): the install smoke below validates the
# built binary against the actual Saphira musl, and no Bun-specific
# stack workarounds exist unless a build genuinely proves them needed.

pkgname=bun
pkgver=1.4.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Bun JavaScript runtime, bundler and package manager"
license="MIT"
origin=bun
repo=saphira
url=https://bun.sh/
source=https://github.com/oven-sh/bun/archive/refs/tags/bun-v1.4.2.tar.gz
sha256=e14670b117d69012d828514d657f0a3133d1c25d13d69461184d05b6a8e9a876

depends=""

makedepends="
    binutils
    cmake
    curl
    gcc
    git
    make
    ninja
    perl
    pkgconf
    python3
    rustc
    unzip
    zig
"
# Ruby is deliberately absent (JSC build scripts may or may not need
# it): if the build fails on a missing ruby interpreter, add it then -
# do not pre-install speculative interpreters.

fatal()
{
	printf 'bun: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	stage0=$BUILDDIR/bun-stage0
	expected=$(awk -F'|' '$5 == "bun-linux-x64-musl-baseline.zip" { print $4; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$expected" || fatal "bootstrap archive is not locked"
	curl -fsSL --retry 3 --output "$BUILDDIR/stage0.zip" \
		"https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-linux-x64-musl-baseline.zip" ||
		fatal "failed to download bootstrap archive"
	printf '%s  %s\n' "$expected" "$BUILDDIR/stage0.zip" | sha256sum -c - ||
		fatal "bootstrap archive checksum mismatch"
	mkdir -p "$stage0"
	unzip -q -o "$BUILDDIR/stage0.zip" -d "$stage0" ||
		fatal "failed to unpack bootstrap archive"
	stage0_bin=$(find "$stage0" -name bun -type f | head -1)
	test -n "$stage0_bin" || fatal "bootstrap archive has no bun binary"
	"$stage0_bin" --version | grep -q "^1.4.2" || fatal "unexpected bootstrap version"
	git clone --recursive --branch bun-v1.4.2 --depth 1 \
		https://github.com/oven-sh/bun.git "$BUILDDIR/bun-src" ||
		fatal "failed to clone bun source (submodules required)"
	cd "$BUILDDIR/bun-src"
	"$stage0_bin" scripts/build.ts --profile=release ||
		fatal "release build failed"
	test -x "$BUILDDIR/bun-src/build/release/bun" ||
		fatal "release binary missing after build"
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/bun-src/build/release/bun" \
		"$PKGDEST/usr/bin/bun"
	# Saphira-musl validation (see header note): version, a hello-world
	# run exercising JSC JIT plus threads, and a file roundtrip. No
	# stack workarounds exist; if these ever fail on thread-stack
	# grounds, that failure is the required proof before adding any.
	"$PKGDEST/usr/bin/bun" --version | grep -q "^1.4.2"
	printf 'console.log("saphira-bun-ok");\n' > "$BUILDDIR/stage0-hello.js"
	"$PKGDEST/usr/bin/bun" "$BUILDDIR/stage0-hello.js" | grep -q saphira-bun-ok
	printf 'hello' > "$BUILDDIR/stage0-in.txt"
	"$PKGDEST/usr/bin/bun" -e 'const d=await Bun.file("'"$BUILDDIR"'/stage0-in.txt").text(); if (d!=="hello") process.exit(1); await Bun.write("'"$BUILDDIR"'/stage0-out.txt", d);' 
	test "$(cat "$BUILDDIR/stage0-out.txt")" = hello
}

#!/bin/sh

pkgname=rustc
pkgver=1.97.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Rust language compiler, cargo, clippy and rustfmt"
license="MIT OR Apache-2.0"
origin=rustc
repo=main
url=https://www.rust-lang.org/
# Official dist source tarball carries the full vendored crate set
# (vendor=true, locked-deps=true below); GitHub tag archives do not.
source=https://static.rust-lang.org/dist/rustc-1.97.1-src.tar.xz
sha256=0ed06fdaffd4722a7702e0b4eebfafc897ab8f513e8e1b247cdd7e5c6df6ded2

depends="
    llvm>=22.1.8-r2
"

makedepends="
    binutils
    curl
    gcc
    llvm>=22.1.8-r2
    make
    openssl-dev
    python3
"

fatal()
{
	printf 'rustc: %s\n' "$1" >&2
	exit 1
}

install_bootstrap_component()
{
	archive=$1
	prefix=$2
	component_dir=$BUILDDIR/bootstrap-components
	expected=$(awk -F'|' -v archive="$archive" '$5 == archive { print $4; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$expected" || fatal "bootstrap archive is not locked: $archive"
	component_archive=$BUILDDIR/$archive
	curl -fsSL --retry 3 --output "$component_archive" \
		"https://static.rust-lang.org/dist/$archive" ||
		fatal "failed to download bootstrap archive: $archive"
	printf '%s  %s\n' "$expected" "$component_archive" | sha256sum -c - ||
		fatal "bootstrap archive checksum mismatch: $archive"
	mkdir -p "$component_dir"
	tar -xf "$component_archive" -C "$component_dir"
	top=$(tar -tf "$component_archive" |
		awk -F/ 'NF { print $1; exit }')
	test -n "$top" || fatal "bootstrap archive has no top-level directory: $archive"
	"$component_dir/$top/install.sh" --prefix="$prefix" \
		--disable-ldconfig --without=rust-docs
}

recipe_build()
{
	bootstrap=$BUILDDIR/bootstrap
	install_bootstrap_component \
		rustc-1.96.0-x86_64-unknown-linux-musl.tar.xz "$bootstrap"
	install_bootstrap_component \
		rust-std-1.96.0-x86_64-unknown-linux-musl.tar.xz "$bootstrap"
	install_bootstrap_component \
		cargo-1.96.0-x86_64-unknown-linux-musl.tar.xz "$bootstrap"
	cat > "$SRC/bootstrap.toml" <<EOF
change-id = "ignore"

[build]
build = "x86_64-unknown-linux-musl"
host = ["x86_64-unknown-linux-musl"]
target = ["x86_64-unknown-linux-musl"]
rustc = "$bootstrap/bin/rustc"
cargo = "$bootstrap/bin/cargo"
python = "/usr/bin/python3"
docs = false
compiler-docs = false
submodules = false
locked-deps = true
vendor = true
extended = true
tools = ["cargo", "clippy", "rustdoc", "rustfmt"]

[install]
prefix = "/usr"
sysconfdir = "/etc"
docdir = "share/doc/rust"

[rust]
channel = "stable"
optimize = true
codegen-units = 1
rpath = true
llvm-tools = true
rustflags = ["-Ctarget-cpu=x86-64-v3", "-Clink-arg=-Wl,--build-id=sha1"]

[llvm]
download-ci-llvm = false
link-shared = true

[target.x86_64-unknown-linux-musl]
cc = "gcc"
cxx = "g++"
ar = "ar"
ranlib = "ranlib"
linker = "gcc"
crt-static = false
llvm-config = "/usr/bin/llvm-config"
llvm-has-rust-patches = false
EOF
	cd "$SRC"
	OPENSSL_DIR=/usr \
	RUSTFLAGS_BOOTSTRAP='-Ctarget-cpu=x86-64-v3 -Clink-arg=-Wl,--build-id=sha1' \
		python3 x.py build --stage 2
}

recipe_install()
{
	cd "$SRC"
	DESTDIR="$PKGDEST" python3 x.py install --stage 2
	install -D -m 0644 "$SRC/LICENSE-APACHE" \
		"$PKGDEST/usr/share/licenses/rustc/LICENSE-APACHE"
	install -m 0644 "$SRC/LICENSE-MIT" \
		"$PKGDEST/usr/share/licenses/rustc/LICENSE-MIT"
	install -m 0644 "$SRC/license-metadata.json" \
		"$PKGDEST/usr/share/licenses/rustc/license-metadata.json"
	install -D -m 0644 "$RECIPE_DIR/files/TRUST.md" \
		"$PKGDEST/usr/share/doc/rust/TRUST.md"
	install -D -m 0755 "$RECIPE_DIR/files/validate-kernel-rust" \
		"$PKGDEST/usr/libexec/akadata/validate-kernel-rust"
	LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/rustc" --version
	LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/cargo" --version
	LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/rustfmt" --version
}

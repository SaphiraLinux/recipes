#!/bin/sh

pkgname=rustc
pkgver=1.97.1
pkgrel=2
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

# openssl-dev is required by openssl-sys's probe when building the
# host tools (cargo links curl/openssl); pkgconf drives that probe.
# The branded build needs it explicitly: with HOST != TARGET the
# openssl-sys build script only succeeds via its pkg-config path,
# and there is no pkg-config binary in the root without this.
# (r1 built without it only by transitive luck, never by design.)
makedepends="
    binutils
    curl
    gcc
    llvm>=22.1.8-r2
    make
    openssl-dev
    pkgconf
    python3
"
# Splits restored (match the published -dev/-doc r0 boundaries):
# self-contained .a libraries belong in -dev, usr/share/doc in -doc
# (the recipe installs TRUST.md there). Man pages are not built
# (docs disabled), so those stale -doc r0 claims touch nothing staged
# and the gate skips them. Without these splits, base r1 reclaims paths
# the r0 splits still own and the file gate refuses.
# r2 keeps cargo in base (no cargo split: the builder only knows
# -dev/-doc/-libs and the controller is not to be extended for
# this; a standalone cargo producer, if wanted, is a recipe-track
# decision for later). drbd-reactor's makedepends on cargo stays
# red until then.
subpackages="rustc-dev rustc-doc"

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
	cd "$SRC"
	patch -p1 < "$RECIPE_DIR/files/akadata-target.patch"
	# Cargo-channeled env for the x.py tool builds (stage2-tools cargo
	# for the akadata host): the build log proves OPENSSL_DIR is unset
	# in openssl-sys's build-script env despite the recipe-process
	# prefix below, so channel it through cargo config (filesystem,
	# always read) instead of process inheritance. /usr (not /usr/lib
	# or lib64): openssl-sys probes lib64-then-lib under the dir and
	# Saphira ships lib-only (/lib, /usr/lib), which the exists-guards
	# handle. PKG_CONFIG_ALLOW_CROSS unblocks the crate's pkg-config
	# path for HOST != TARGET against the same /usr.
	mkdir -p "$SRC/.cargo"
	cat > "$SRC/.cargo/config.toml" <<EOF
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"

[env]
OPENSSL_DIR = "/usr"
PKG_CONFIG_ALLOW_CROSS = "1"
EOF
	bootstrap=$BUILDDIR/bootstrap
	install_bootstrap_component \
		rustc-1.96.0-x86_64-unknown-linux-musl.tar.xz "$bootstrap"
	install_bootstrap_component \
		rust-std-1.96.0-x86_64-unknown-linux-musl.tar.xz "$bootstrap"
	install_bootstrap_component \
		cargo-1.96.0-x86_64-unknown-linux-musl.tar.xz "$bootstrap"
	cat > "$SRC/bootstrap.toml" <<EOF
change-id = "ignore"

# Branded bootstrap: the stage0/build machine stays
# x86_64-unknown-linux-musl (the old working compiler), while host and
# target become x86_64-akadata-linux-musl. BOTH target sections are
# deliberate: x.py still needs build-tuple tool settings while
# constructing stage1, and must not fall back to plain cc there.
[build]
build = "x86_64-unknown-linux-musl"
host = ["x86_64-akadata-linux-musl"]
target = ["x86_64-akadata-linux-musl"]
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
cc = "x86_64-akadata-linux-musl-gcc"
cxx = "x86_64-akadata-linux-musl-g++"
ar = "ar"
ranlib = "ranlib"
linker = "x86_64-akadata-linux-musl-gcc"
crt-static = false
# Explicit (not the /usr fallback): bootstrap only applies the fallback
# to its primary host_target (= build = unknown here), so the branded
# host needs its own. Clean roots carry musl + musl-dev in the seed.
musl-root = "/usr"
llvm-config = "/usr/bin/llvm-config"
llvm-has-rust-patches = false

[target.x86_64-akadata-linux-musl]
cc = "x86_64-akadata-linux-musl-gcc"
cxx = "x86_64-akadata-linux-musl-g++"
ar = "ar"
ranlib = "ranlib"
linker = "x86_64-akadata-linux-musl-gcc"
crt-static = false
musl-root = "/usr"
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
	# Branded-host acceptance: the stage2 compiler must report the
	# AKADATA triple, not the bootstrap seed's unknown tuple.
	# Captured comparison (not `... | grep -q ...`): a direct
	# grep -q pipeline false-negatived here under set -o pipefail
	# while every staged binary reports the branded host. The
	# actual value is echoed on mismatch so the next failure is
	# self-diagnosing instead of a bare fatal.
	stage2_host="$(LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/rustc" -vV | grep '^host: ' || true)"
	test "$stage2_host" = "host: x86_64-akadata-linux-musl" ||
		fatal "stage2 rustc host is not x86_64-akadata-linux-musl (got: $stage2_host)"
	stage2_targets="$(LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		"$PKGDEST/usr/bin/rustc" --print target-list || true)"
	printf '%s\n' "$stage2_targets" | grep -qx 'x86_64-akadata-linux-musl' ||
		fatal "stage2 rustc does not enumerate x86_64-akadata-linux-musl"
}

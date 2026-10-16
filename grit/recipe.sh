#!/bin/sh

pkgname=grit
pkgver=0.4.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Coordination layer for parallel AI agents on top of git'
license='Apache-2.0'
origin=grit
repo=main
url=https://github.com/rtk-ai/grit
# Pinned upstream v0.4.0 tag archive. No vendored crates upstream, so
# crates are fetched per-crate and verified against crates.lock (pinned
# URL + sha256 per crate), matching the proven ripgrep pattern.
source=https://github.com/rtk-ai/grit/archive/refs/tags/v0.4.0.tar.gz
sha256=41612fc0f6afed9429828b3b440f0b94d3026f621644749658dae06860da97b4

# openssl: openssl-sys links the system libssl/libcrypto dynamically
# (native-tls/hyper-tls backends). pkgconf drives its probe.
depends="
    openssl
"

# aws-lc-sys builds its C sources via the cmake binary; tree-sitter
# parsers and rusqlite(bundled)/ring need a C compiler; libunwind-dev
# supplies the static libunwind.a that build-script linking needs on
# the static-PIE target (ripgrep precedent); curl drives the per-crate
# fetch loop below.
makedepends="
    binutils
    cmake
    curl
    gcc
    libunwind-dev
    make
    openssl-dev
    pkgconf
    python3
    rustc>=1.97.1-r1
"

fatal()
{
	printf 'grit: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	vendor=$BUILDDIR/vendor
	mkdir -p "$vendor" "$SRC/.cargo"
	# Loop variables must stay function-local: url/license collide with
	# builder metadata globals, and the final failing read would otherwise
	# clear them (empty license/url in the normalized manifest).
	local source version url checksum archive license
	while IFS='|' read -r source version url checksum archive license; do
		name=${source#grit-crate-}
		name=${name%-$version}
		crate_archive=$BUILDDIR/$archive
		curl -fsSL --retry 3 --output "$crate_archive" "$url" ||
			fatal "failed to download locked crate: $name $version"
		printf '%s  %s\n' "$checksum" "$crate_archive" | sha256sum -c - ||
			fatal "locked crate checksum mismatch: $name $version"
		tar --no-same-owner -xf "$crate_archive" -C "$vendor"
		crate_dir=$vendor/$name-$version
		test -d "$crate_dir" ||
			fatal "locked crate archive has unexpected layout: $name $version"
		python3 - "$crate_dir" "$checksum" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
files = {}
for path in sorted(root.rglob("*")):
    if path.is_file() and path.name != ".cargo-checksum.json":
        files[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
(root / ".cargo-checksum.json").write_text(
    json.dumps({"files": files, "package": sys.argv[2]}, sort_keys=True, separators=(",", ":")) + "\n"
)
PY
	done < "$RECIPE_DIR/crates.lock"
	cat > "$SRC/.cargo/config.toml" <<EOF
[source.crates-io]
replace-with = "saphira-vendored"

[source.saphira-vendored]
directory = "$vendor"
EOF
	cd "$SRC"
	# No -Clink-arg=-no-pie: the Saphira akadata target builds static-PIE
	# (static_position_independent_executables) and rustc links its
	# bundled static-PIE CRT; appending -no-pie forces EXEC output
	# from PIE startup objects and every emitted executable dies in
	# pre-main startup (deterministic SIGSEGV, proven on ripgrep's
	# serde_json build script).
	OPENSSL_DIR=/usr \
	CARGO_HOME=$BUILDDIR/cargo-home \
		RUSTFLAGS='-Ctarget-cpu=x86-64-v3 -Clink-arg=-Wl,--build-id=sha1' \
		cargo build --frozen --offline --release
}

recipe_install()
{
	vendor=$BUILDDIR/vendor
	license_root=$PKGDEST/usr/share/licenses/grit
	install -D -m 0755 "$SRC/target/release/grit" \
		"$PKGDEST/usr/bin/grit"
	install -D -m 0644 "$SRC/LICENSE" \
		"$license_root/LICENSE"
	install -D -m 0644 "$SRC/README.md" \
		"$PKGDEST/usr/share/doc/grit/README.md"
	# Per-crate licence harvest (bindgen pattern): every vendored
	# dependency's own licence text ships alongside the binary.
	for directory in "$vendor"/*; do
		name=${directory##*/}
		find "$directory" -maxdepth 1 -type f \
			\( -iname 'license*' -o -iname 'copying*' -o -iname 'unlicense*' \) \
			-print | while IFS= read -r file; do
			install -D -m 0644 "$file" \
				"$license_root/crates/$name/${file##*/}"
		done
	done
	# Smoke check: the staged binary executes (--version only prints
	# and exits; no repo state, no config, no home-directory writes).
	"$PKGDEST/usr/bin/grit" --version
}

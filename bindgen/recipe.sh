#!/bin/sh

pkgname=bindgen
pkgver=0.72.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Rust bindgen: automatically generates Rust FFI bindings to C libraries"
license="Apache-2.0 OR MIT"
origin=bindgen
repo=saphira
url=https://github.com/rust-lang/rust-bindgen
# GitHub tag archive: no vendored crates, so crates are fetched per-crate
# and verified against crates.lock (pinned URL + sha256 per crate),
# matching the ripgrep vendored-source pattern and the proven v0 build.
source=https://github.com/rust-lang/rust-bindgen/archive/refs/tags/v0.72.1.tar.gz
sha256=4ffb17061b2d71f19c5062d2e17e64107248f484f9775c0b7d30a16a8238dfd1

depends="
    libclang>=22.1.8-r1
"

makedepends="
    binutils
    curl
    gcc
    libclang>=22.1.8-r1
    llvm>=22.1.8-r1
    openssl-dev
    python3
    rustc>=1.97.1-r1
"

fatal()
{
	printf 'bindgen: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	vendor=$BUILDDIR/vendor
	mkdir -p "$vendor" "$SRC/.cargo"
	while IFS='|' read -r source version url checksum archive license; do
		name=${source#bindgen-crate-}
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
	CARGO_HOME=$BUILDDIR/cargo-home \
		LIBCLANG_PATH=/usr/lib CLANG_PATH=/usr/bin/clang \
		OPENSSL_DIR=/usr \
		cargo build --frozen --offline --release --package bindgen-cli
}

recipe_install()
{
	vendor=$BUILDDIR/vendor
	license_root=$PKGDEST/usr/share/licenses/bindgen
	install -D -m 0755 "$SRC/target/release/bindgen" \
		"$PKGDEST/usr/bin/bindgen"
	install -D -m 0644 "$SRC/LICENSE" \
		"$license_root/LICENSE"
	for directory in "$vendor"/*; do
		name=${directory##*/}
		find "$directory" -maxdepth 1 -type f \
			\( -iname 'license*' -o -iname 'copying*' -o -iname 'unlicense*' \) \
			-print | while IFS= read -r file; do
			install -D -m 0644 "$file" \
				"$license_root/crates/$name/${file##*/}"
		done
	done
}

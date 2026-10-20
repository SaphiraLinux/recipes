#!/bin/sh

pkgname=cbindgen
pkgver=0.29.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="C/C++ header generator for Rust FFI (mesa nouveau NIL requirement)"
license='MPL-2.0'
origin=cbindgen
repo=saphira
url=https://github.com/mozilla/cbindgen
# GitHub tag archive: no vendored crates, so crates are fetched per-crate
# and verified against crates.lock (pinned URL + sha256 per crate),
# matching the ripgrep/bindgen vendored-source pattern.
source=https://github.com/mozilla/cbindgen/archive/refs/tags/v0.29.4.tar.gz
sha256=9b5757e915cf8be523d3aca282b9b5651bafa112e14bf1ba488562ba282807d6

depends=""

makedepends="
    binutils
    curl
    gcc
    libunwind-dev
    python3
    rustc
"

fatal()
{
	printf 'cbindgen: %s\n' "$1" >&2
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
		name=${source#cbindgen-crate-}
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
		cargo build --frozen --offline --release
}

recipe_install()
{
	install -D -m 0755 "$SRC/target/release/cbindgen" \
		"$PKGDEST/usr/bin/cbindgen"
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/cbindgen/LICENSE"
}

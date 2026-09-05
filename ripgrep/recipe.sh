#!/bin/sh

pkgname=ripgrep
pkgver=15.2.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Fast line-oriented reverse regex search tool (rg)"
license="MIT OR Unlicense"
origin=ripgrep
repo=main
url=https://github.com/BurntSushi/ripgrep
# GitHub tag archive: no vendored crates, so crates are fetched per-crate and
# verified against crates.lock (pinned URL + sha256 per crate), matching the
# proven v0 vendored-source build.
source=https://github.com/BurntSushi/ripgrep/archive/refs/tags/15.2.0.tar.gz
sha256=7605249d3eb0d5f170e3414498e3344e26b1e7a147aec518b57090b80036a562

makedepends="
    binutils
    curl
    gcc
    libunwind-dev>=22.1.8-r1
    make
    openssl-dev
    python3
    rustc>=1.97.1-r1
"

fatal()
{
	printf 'ripgrep: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	vendor=$BUILDDIR/vendor
	mkdir -p "$vendor" "$SRC/.cargo"
	while IFS='|' read -r source version url checksum archive license; do
		name=${source#ripgrep-crate-}
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
		RUSTFLAGS="-Ctarget-cpu=x86-64-v3 -Clink-arg=-Wl,--build-id=sha1 -Clink-arg=-no-pie" \
		OPENSSL_DIR=/usr \
		cargo build --frozen --offline --profile release-lto
}

recipe_install()
{
	install -D -m 0755 "$SRC/target/release-lto/rg" \
		"$PKGDEST/usr/bin/rg"
	install -D -m 0644 "$SRC/LICENSE-MIT" \
		"$PKGDEST/usr/share/licenses/ripgrep/LICENSE-MIT"
	install -m 0644 "$SRC/UNLICENSE" \
		"$PKGDEST/usr/share/licenses/ripgrep/UNLICENSE"
}

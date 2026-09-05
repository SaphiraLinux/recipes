#!/bin/sh

pkgname=phetch
pkgver=1.2.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Phetch: quick little terminal Gopher client (RFC 1436, TLS + Tor)'
license='MIT'
origin=phetch
repo=saphira
url=https://github.com/xvxx/phetch
# Pinned upstream release from crates.io (immutable artifact with a
# publisher-verified checksum).  1.2.0 is the newest upstream release
# (default features: tls + tor, both within the native dependency
# closure: native-tls -> openssl; tor-stream -> socks, pure Rust).
source=https://static.crates.io/crates/phetch/phetch-${pkgver}.crate
sha256=a0806d2ea41a70dd803f9a0d8c670995c71982f8e333919251c8fbe004f2de11

depends="
    openssl
"

# Native Saphira Rust toolchain model (same as ripgrep): pinned rustc
# + per-crate vendoring driven by crates.lock (pinned URL + sha256 per
# crate).  openssl-dev is required by openssl-sys's pkg-config probe;
# pkgconf drives it.
makedepends="
    binutils
    curl
    gcc
    make
    openssl-dev
    pkgconf
    python3
    rustc>=1.97.1-r1
"

fatal()
{
	printf 'phetch: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	vendor=$BUILDDIR/vendor
	mkdir -p "$vendor" "$SRC/.cargo"
	while IFS='|' read -r source version url checksum archive license; do
		name=${source#phetch-crate-}
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
		RUSTFLAGS='-Ctarget-cpu=x86-64-v3 -Clink-arg=-Wl,--build-id=sha1' \
		cargo build --frozen --offline --release
}

recipe_install()
{
	install -Dm0755 "$SRC/target/release/phetch" \
		"$PKGDEST/usr/bin/phetch"
}

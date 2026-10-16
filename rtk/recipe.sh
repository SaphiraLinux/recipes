#!/bin/sh

pkgname=rtk
pkgver=1.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='CLI proxy that reduces LLM token consumption on dev commands (full edition)'
# Mixed upstream licensing, preserved exactly (operator decision: build the
# normal full edition, never --no-default-features):
#   core CLI (src/, text/, plugin/, hooks/) ......... Apache-2.0
#   engine/ (rtk-engine, linked into the shipped binary) .. BUSL-1.1,
#     Licensor RTK AI Labs, Change Date 2030-09-09,
#     Change License Apache-2.0; Additional Use Grant covers production
#     use as a component of the rtk binary (see engine/LICENSE).
# These are upstream terms, NOT Saphira/AKADATA licensing language.
# The BUSL parts are source-available, not open source.
# proxy/ (rtk-proxy daemon) is also upstream BUSL-1.1 but is NOT built
# or shipped here: it is a non-workspace member with its own lockfile
# and ships as its own archive upstream.
license='Apache-2.0 AND BUSL-1.1'
origin=rtk
repo=main
url=https://github.com/rtk-ai/rtk
# Pinned upstream v1.0.0 tag archive. No vendored crates upstream, so
# crates are fetched per-crate and verified against crates.lock (pinned
# URL + sha256 per crate), matching the proven ripgrep pattern.
source=https://github.com/rtk-ai/rtk/archive/refs/tags/v1.0.0.tar.gz
sha256=9dd0492c5acc9f6aec39b7e352d499392186274bab02443dc56073971a16f02e

# No openssl-sys in the rtk CLI closure (ureq v2 uses rustls; rusqlite
# is bundled/static), so no openssl-dev. No cmake/perl/nasm/protoc.
# libunwind-dev supplies the static libunwind.a that build-script
# linking needs on the static-PIE target (ripgrep precedent).
# curl drives the per-crate fetch loop below.
makedepends="
    binutils
    curl
    gcc
    libunwind-dev
    make
    python3
    rustc>=1.97.1-r1
"

fatal()
{
	printf 'rtk: %s\n' "$1" >&2
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
		name=${source#rtk-crate-}
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
	# Full upstream edition (default features link the BUSL-1.1
	# rtk-engine). -p rtk keeps the non-workspace proxy/ daemon out
	# of this build: no rtk-proxy binary, no daemon payload.
	# No -Clink-arg=-no-pie: the Saphira akadata target builds static-PIE
	# (static_position_independent_executables) and rustc links its
	# bundled static-PIE CRT; appending -no-pie forces EXEC output
	# from PIE startup objects and every emitted executable dies in
	# pre-main startup (deterministic SIGSEGV, proven on ripgrep's
	# serde_json build script).
	CARGO_HOME=$BUILDDIR/cargo-home \
		RUSTFLAGS='-Ctarget-cpu=x86-64-v3 -Clink-arg=-Wl,--build-id=sha1' \
		cargo build --frozen --offline --release -p rtk
}

recipe_install()
{
	vendor=$BUILDDIR/vendor
	license_root=$PKGDEST/usr/share/licenses/rtk
	install -D -m 0755 "$SRC/target/release/rtk" \
		"$PKGDEST/usr/bin/rtk"
	# Upstream licence texts, shipped verbatim: Apache-2.0 core plus
	# the BUSL-1.1 engine parameters/Additional Use Grant/Change Date.
	install -D -m 0644 "$SRC/LICENSE" \
		"$license_root/LICENSE"
	install -D -m 0644 "$SRC/engine/LICENSE" \
		"$license_root/LICENSE-ENGINE"
	install -D -m 0644 "$SRC/README.md" \
		"$PKGDEST/usr/share/doc/rtk/README.md"
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
	# Smoke check: the staged binary executes (no init, no config,
	# no home-directory writes; --version only prints and exits).
	"$PKGDEST/usr/bin/rtk" --version
}

#!/bin/sh

pkgname=python-cryptography
pkgver=46.0.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Cryptographic recipes and primitives for Python (Rust-backed)"
license="Apache-2.0 OR BSD-3-Clause"
origin=python-cryptography
repo=saphira
url=https://github.com/pyca/cryptography
source=https://files.pythonhosted.org/packages/source/c/cryptography/cryptography-46.0.2.tar.gz
sha256=21b6fc8c71a3f9a604f028a329e5560009cc4a3a828bfea5fcba8eb7647d88fe

depends="
    python-cffi
    python3
    python3-dev
    setuptools
"

makedepends="
    binutils
    curl
    gcc
    libffi-dev
    make
    openssl-dev
    pkgconf
    python3
    python3-dev
    setuptools
    rustc>=1.97.1-r1
"

# Rust extension vendored per-crate against crates.lock (proven v0
# pattern, also used by ripgrep/bindgen). OPENSSL_NO_VENDOR=1 links the
# native openssl; dynamic libstd via -crt-static (musl default blocks
# dylib consumers otherwise).
fatal()
{
	printf 'python-cryptography: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	vendor=$BUILDDIR/vendor
	mkdir -p "$vendor" "$SRC/.cargo"
	while IFS='|' read -r source version url checksum archive license; do
		crate_archive=$BUILDDIR/$archive
		curl -fsSL --retry 3 --output "$crate_archive" "$url" ||
			fatal "failed to download locked crate: $archive"
		printf '%s  %s\n' "$checksum" "$crate_archive" | sha256sum -c - ||
			fatal "locked crate checksum mismatch: $archive"
		tar --no-same-owner -xf "$crate_archive" -C "$vendor"
		crate_dir=$vendor/${archive%.crate}
		test -d "$crate_dir" ||
			fatal "locked crate archive has unexpected layout: $archive"
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
		PYO3_PYTHON=/usr/bin/python3 OPENSSL_NO_VENDOR=1 \
		RUSTFLAGS='-Ctarget-cpu=x86-64-v3 -Ctarget-feature=-crt-static -Clink-arg=-Wl,--build-id=sha1' \
		cargo build --frozen --offline --release --package cryptography-rust
}

recipe_install()
{
	site=$PKGDEST/usr/lib/python3.14/site-packages
	install -d -m 0755 "$site/cryptography/hazmat/bindings" \
		"$site/cryptography-46.0.2.dist-info"
	cp -a "$SRC/src/cryptography/." "$site/cryptography/"
	install -m 0755 "$SRC/target/release/libcryptography_rust.so" \
		"$site/cryptography/hazmat/bindings/_rust.abi3.so"
	install -m 0644 "$SRC/PKG-INFO" \
		"$site/cryptography-46.0.2.dist-info/METADATA"
	PYTHONPATH="$site" LD_LIBRARY_PATH="$PKGDEST/usr/lib" \
		/usr/bin/python3 -c 'import cryptography; from cryptography.hazmat.bindings import _rust; print(cryptography.__version__)'
}

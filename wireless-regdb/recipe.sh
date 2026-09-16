pkgname=wireless-regdb
pkgver=2026.05.30
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira-signed wireless regulatory database'
license=ISC
origin=wireless-regdb
repo=main
url=https://wireless.wiki.kernel.org/en/developers/regulatory/wireless-regdb
source=https://mirrors.edge.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-2026.05.30.tar.xz
sha256=8a27bfc081bafed8c24dd70fab0d96f098e5a0bfcd08d3da672595f225ab8993

makedepends="gcc make openssl"

recipe_build()
{
	# Vendored tarball (bytes pinned, hash matches the upstream URL pin):
	# in the staged-/input regime the worker skips archive download and
	# extraction entirely.
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/wireless-regdb-2026.05.30.tar.xz"
	echo "$sha256  $RECIPE_DIR/files/wireless-regdb-2026.05.30.tar.xz" | sha256sum -c -
	make regulatory.db
	KEY="$SRC/saphira-regdb.pem"
	[ -f "$KEY" ] || { echo "ERROR: regdb signing key missing at $KEY (staged /input?)" >&2; return 1; }
	# -nosmimecap is load-bearing: plain openssl cms -sign embeds an
	# S/MIME Capabilities signed-attribute that the kernel's strict
	# PKCS#7 parser rejects (dmesg "PKCS7: S/MIME Caps only allowed with
	# Authenticode", then "regulatory.db is malformed or signature is
	# missing/invalid", country stuck at 00 - proven on Hatched with a
	# keyid-matching, openssl-verifiable .p7s). Bare attributes pass.
	openssl cms -sign -binary -md sha256 -nosmimecap \
		-in regulatory.db \
		-signer "$KEY" -inkey "$KEY" \
		-outform DER -out regulatory.db.p7s
}

recipe_install()
{
	# /lib/firmware: the kernel loader's hardcoded path on non-usrmerged
	# Saphira. /usr/lib/firmware (r2 and earlier) is invisible to it -
	# the db sat installed yet unloadable (world-domain fallback).
	# r3: path fix + nosmimecap re-sign (see above).
	install -d "$PKGDEST/lib/firmware"
	install -m 644 "$SRC/regulatory.db" "$PKGDEST/lib/firmware/regulatory.db"
	install -m 644 "$SRC/regulatory.db.p7s" "$PKGDEST/lib/firmware/regulatory.db.p7s"
}

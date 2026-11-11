#!/bin/sh

pkgname=cryptsetup
pkgver=2.8.8
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='LUKS/dm-crypt volume setup tool (libcryptsetup plus utilities)'
license='GPL-2.0-or-later WITH cryptsetup-OpenSSL-exception'
origin=cryptsetup
repo=saphira
url=https://gitlab.com/cryptsetup/cryptsetup
source=https://www.kernel.org/pub/linux/utils/cryptsetup/v2.8/cryptsetup-2.8.8.tar.xz
sha256=3acfa685f2dd7fcc832e0b77bc7093aa7da554a51ce8dafbb4138eaa854eee35

# Three-way split (lvm2 doctrine): consumers take -dev to build and
# -libs to run; nothing takes main for headers. The tools link
# libcryptsetup plus popt/uuid/blkid directly (per-object DT_NEEDED,
# proven Minimer 2026-11-08: cryptsetup/veritysetup/integritysetup),
# so main carries exactly those three providers.
# The lib's own DT_NEEDED closure (json-c, libdevmapper, libcrypto,
# uuid, blkid) rides depends_libs on the -libs split itself: a
# standalone cryptsetup-libs install without it loads a library whose
# requirements are unmet (libjson-c.so.5 absent after a cryptsetup-only
# install broke every lib consumer at exec, same Minimer proof).
subpackages="cryptsetup-dev cryptsetup-libs $pkgname-doc"
depends="cryptsetup-libs popt util-linux"
depends_libs="json-c lvm2-libs openssl util-linux"
depends_dev="json-c-dev lvm2-dev openssl-dev util-linux-dev"

makedepends="
	asciidoctor
	gcc
	gettext
	json-c-dev
	lvm2-dev
	make
	openssl-dev
	pkgconf
	popt-dev
	saphira-linux-uapi-headers
	util-linux-dev
"

# cryptsetup 2.8.8: latest signed tag (2026-09-07), sha verified
# against kernel.org sha256sums. Autotools build (Alpine parity).
#
# Explicit flags, evidence in configure.ac + Alpine main/cryptsetup:
# - openssl backend (default): the systemd consumer links
#   libcryptsetup against openssl; gcrypt/nss/nettle/mbedtls are
#   alternate backends, not additional features.
# - internal argon2: LOCKED operator choice for this port. Counter-
#   evidence on record: libargon2-20190702-r2 is published and
#   upstream + Alpine prefer --enable-libargon2 (bundled code is
#   the slow reference). One-word flip later if directed.
#   internal-sse stays at upstream default (off, not in the lock).
# - udev enabled (checkpoint); configure degrades to a warning if
#   lvm2's libdevmapper lacks the udev cookie decls (lvm2 builds
#   --disable-udev_sync) - the log decides, the build stays green.
# - blkid/keyring/kernel_crypto/luks2-reencryption/tools all enabled
#   explicitly (headers present: util-linux-dev, uapi headers).
# - external-tokens + ssh-token DISABLED: external tokens need
#   dlvsym(3), a GNU extension absent on musl (Alpine documents
#   this), and ssh-token refuses to build without external tokens.
#   This is a libc boundary, not a feature cut: libssh is published
#   but unusable here until musl gains dlvsym. No argp/libssh in
#   makedepends for the same reason.
# - selinux flag omitted deliberately: it gates only the static
#   build path (no shared-build probe exists); static is off.
# - man pages: the tarball SHIPS prebuilt .8 files (generated with
#   Asciidoctor 2.0.26, which independently confirms our asciidoctor
#   pin) and configure re-uses them, but --enable-asciidoc still
#   fails closed without asciidoctor in the build root - so the doc
#   toolchain stays a real, verified dependency, no exception.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/cryptsetup-${pkgver}.tar.xz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/cryptsetup-${pkgver}.tar.xz"

	cd "$SRC"

	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-static \
		--enable-asciidoc \
		--with-crypto_backend=openssl \
		--enable-internal-argon2 \
		--enable-udev \
		--enable-blkid \
		--enable-keyring \
		--enable-kernel_crypto \
		--enable-luks2-reencryption \
		--enable-cryptsetup \
		--enable-veritysetup \
		--enable-integritysetup \
		--disable-external-tokens \
		--disable-ssh-token \
		--enable-nls
	make -j${JOBS:-$(nproc)}
	# Unit gate only (systemd integration-tests precedent): the full
	# `make check` needs kernel device-mapper (/dev/mapper/control)
	# plus loop devices, which the rootless build sandbox cannot
	# provide (mknod denied) - every dm/loop/keyring test fails
	# there for environmental reasons, not code reasons. The three
	# device-free programs below are proven so from source (no
	# mapper or /dev references): crypto vectors, utils unit tests,
	# exported-symbol surface. check_PROGRAMS still COMPILES the
	# whole suite, so nothing goes unbuilt; device integration is
	# proven at deploy time (Minimer/firstboot), like systemd's.
	make check TESTS="vectors-test unit-utils-crypt-test run-all-symbols"
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install

	install -m644 "$SRC/README.md" "$SRC/FAQ.md" \
		"$SRC/docs/v${pkgver}-ReleaseNotes" \
		"$PKGDEST/usr/share/doc/$pkgname/" 2>/dev/null || {
		install -d "$PKGDEST/usr/share/doc/$pkgname"
		install -m644 "$SRC/README.md" "$SRC/FAQ.md" \
			"$SRC/docs/v${pkgver}-ReleaseNotes" \
			"$PKGDEST/usr/share/doc/$pkgname/"
	}

	# FHS non-usrmerged (util-linux idiom): the units and init
	# scripts expect the tools in /sbin, not /usr/sbin.
	install -d "$PKGDEST/sbin"
	for tool in cryptsetup veritysetup integritysetup; do
		[ -x "$PKGDEST/usr/sbin/$tool" ] && \
			mv "$PKGDEST/usr/sbin/$tool" "$PKGDEST/sbin/$tool"
	done
	if [ -d "$PKGDEST/usr/sbin" ]; then
		[ -z "$(ls -A "$PKGDEST/usr/sbin")" ] || {
			echo "cryptsetup: unexpected residue in /usr/sbin:" >&2
			ls -A "$PKGDEST/usr/sbin" >&2
			exit 1
		}
	fi

	# Runtime library placement (zlib/acl idiom): /sbin consumers
	# need the SONAME chain in /lib; the dev linker name stays in
	# /usr/lib pointing back (picked up by -dev/-libs splits).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libcryptsetup.so.12"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	link="$PKGDEST/usr/lib/libcryptsetup.so"
	if [ -L "$link" ]; then
		target=$(readlink "$link")
		case $target in */*) :;; *) [ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link";; esac
	fi

	find "$PKGDEST" -name '*.la' -delete

	for tool in cryptsetup veritysetup integritysetup; do
		test -x "$PKGDEST/sbin/$tool" || {
			echo "cryptsetup: missing /sbin/$tool" >&2
			exit 1
		}
	done
	test -n "$(find "$PKGDEST/lib" -name 'libcryptsetup.so.*' -print -quit)"
	for page in cryptsetup veritysetup integritysetup; do
		test -f "$PKGDEST/usr/share/man/man8/$page.8" || {
			echo "cryptsetup: missing man page $page.8" >&2
			exit 1
		}
	done
}

pkgname=saphira-kernel
# Package version must be a valid apk version, and an apk version cannot
# contain a hyphen before -rN. That is invisible on every stable line
# (7.2.2-r10 is fine) and only bites the pre-release line: SAPHIRA_KERNEL_VERSION
# selects the vendored tarball and config, whose names legitimately use a
# hyphen (linux-7.3-rc1.tar.gz, config-7.3-rc1-akadata), so 7.3-rc1 reached
# makepkg and was rejected with "info field 'version' has invalid value".
#
# Saphira's own convention for a pre-release pkgver is an underscore, exactly
# as the rest of the repository does it: openssh 10.5_p1, sudo 1.9.17_p2,
# qmail 2026.09.08_rc1. So the hyphen becomes an underscore and nothing else
# changes. Stable lines are untouched, because they contain no hyphen.
#
# The upstream kernel release string keeps its own hyphen and is unaffected:
# modules for this line install under /lib/modules/7.3.0-rc1, and KREL is
# derived from the tree rather than from pkgver.
# kernel_version selects the SOURCE line: the vendored tarball name, the
# config file name and the vendor/sha256 pin table below, all of which
# legitimately use the upstream hyphen (linux-7.3-rc1.tar.gz,
# config-7.3-rc1-akadata, case 7.3-rc1). pkgver is the PACKAGE version, which
# apk requires to be a valid apk version and therefore cannot carry a hyphen
# before -rN. Keeping them as separate variables is what stops one from
# silently breaking the other: deriving pkgver from kernel_version and leaving
# the pin table on kernel_version means neither can invalidate the other.
kernel_version=${SAPHIRA_KERNEL_VERSION:-7.2.2}
# Bash parameter expansion, deliberately not `tr`: the metadata probe evaluates
# this recipe in a sandbox that binds only /bin /lib /usr /recipe, so an
# external binary that depends on PATH is a portability hazard, and a recipe
# that cannot be read by the probe cannot be built at all.
pkgver=${kernel_version//-/_}
pkgrel=11
# LEGACY IDENTITY, DISABLED: single-name saphira-kernel is superseded by
# the per-$kver saphira-kernel-7.1.5/-7.2.2/-7.2.3/-7.3-rc1 recipes, which
# apk treats as independently installable kernels. This recipe stays only
# as build/reference history for the T7 migration design; it must never
# build or publish again (a single-name build would collide with every
# versioned successor in the repository gate).
disabled=yes
disabled_reason='superseded by per-kver saphira-kernel-7.1.5/-7.2.2/-7.2.3/-7.3-rc1 (co-installable identities; legacy migration is explicit, never automatic)'
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira kernel ${kernel_version} (x86-64-v3, signed modules, Saphira regdb trust)"
license=GPL-2.0-only
origin=saphira-kernel
repo=saphira
url=https://saphira.vm2.uk/

# RELEASE NOTE (read this before assuming a size change is a mistake)
#
# saphira-kernel 7.2.2-r7, -r8 and -r9 are retained intentionally and
# permanently as historical release artefacts. A packaging regression
# introduced kernel build-source payload and unstripped debug-heavy modules,
# causing a large size increase (32 MiB -> 600 MiB compressed; 70 MiB ->
# ~2.4 GiB installed). The issue was identified, acknowledged and corrected
# in a later immutable revision.
#
# Previous signed artefacts have not been altered or removed. Saphira does
# not hide its mistakes: the oversized packages stay in the repository so the
# regression is auditable rather than merely confessed, and so nobody
# re-derives the same mistake believing it was never made. If you are
# auditing a size regression, compare against r5 (the last known-good
# packaging, 32 MiB / ~70 MiB installed) and read the history here.
#
# r10 restores the production debug policy (CONFIG_DEBUG_INFO_NONE=y) and
# removes /usr/src and the module build/source symlinks from the payload. The
# runtime hardware, networking and BPF LSM configuration is unchanged.
# Upstream kernel tarball per version line (SAPHIRA_KERNEL_VERSION selects).
# vendor=+sha256= is the fetch contract: when the archive is absent from
# files/, the builder downloads vendor=, verifies sha256, and exposes the
# verified archive as $SOURCE_ARCHIVE (kernel.org signs the UNCOMPRESSED
# .tar; verify procedure: xz -dc file.xz > file.tar && gpg --verify
# file.tar.sign file.tar). 7.3-rc1 is a torvalds-tree cgit snapshot
# (unsigned by nature; TLS fetch + sha256 pin, same as other payloads).
case "$kernel_version" in
	7.1.5)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.1.5.tar.xz
		sha256=22a0196b3cbcdf34dc27b77561f4d040585fd3447edc9ab3531a1ac79e3041e7
		;;
	7.2.2)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.2.tar.xz
		sha256=7d0e7ce14f98c43efe880cffbf354a59be45928fdf7170d7333c374ae91c0d83
		;;
	7.2.3)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.3.tar.xz
		sha256=8ba259e8e7b13ec6ef0941c8a39ad90b24bd4a4d6c0010ba6bafb794550ecd03
		;;
	7.3-rc1)
		vendor=https://git.kernel.org/torvalds/t/linux-7.3-rc1.tar.gz
		sha256=8d36fbfc7c8906ccfa1ebacc30f84998406504c3f13733a040bb3a3fbe8ac270
		;;
	*) echo "ERROR: no pinned vendor/sha256 for kernel $kernel_version" >&2; return 1 ;;
esac

# Build secret contract: module signing is mandatory, never optional.
# The worker refuses before spending anything when the builder did
# not expose a readable /keys/module-signing.pem.
saphira_sign_key_required=yes
makedepends="
	bc
	binutils
	kmod
	elfutils-dev
	bison
	m4
	flex
	gawk
	gcc
	openssl-dev
	make
	perl
	pahole
	zlib-dev
"
# pahole is required by CONFIG_DEBUG_INFO_BTF, which the 7.2.2 config
# enables. BTF generation is not optional garnish: it is what lets a
# vmlinux.h be derived from THIS kernel, which systemd's BPF
# userns-restriction program needs in order to be built. elfutils-dev was
# already here for other reasons; pahole itself is the new input. The
# config records CONFIG_PAHOLE_VERSION=131, so the build detects the tool
# at build time and a missing or older pahole shows up as BTF silently
# not being generated -- hence it is a hard makedepends entry rather than
# a note.
#
# zlib-dev has the same kind of evidence behind it, and the same reason to
# be a hard entry rather than a note. Enabling BTF makes the kernel build
# tools/bpf/resolve_btfids, which compiles the bundled libbpf, and
# tools/lib/bpf/libbpf.c includes <zlib.h> (and <libelf.h>/<gelf.h>, which
# elfutils-dev already provides). Without it the build died at
# libbpf.c:48: fatal error: zlib.h: No such file or directory.

# Build inputs: none beyond the recipe tree. The module signing key is
# exposed by the builder (fixed in-namespace path); no /input staging.
# Regdb trust: public DER cert ships in files/ and is compiled into cfg80211
# via CONFIG_CFG80211_EXTRA_REGDB_KEYDIR. Saphira policy patches live in
# files/: x86-64-v3.patch, config-${kernel_version}-akadata. Note these
# follow kernel_version, not pkgver: the payload is named after the KERNEL,
# and config-<kver>-akadata is the name the layout gate, the kmod
# provenance gate and the release guard all look for.

recipe_build()
{
	# Module signing key: exposed by the builder read-only at the fixed
	# in-namespace path /keys/module-signing.pem (canonical host key
	# /etc/saphira/keys/module-signing.pem, never in /recipes, never
	# staged through /build). Absent key fails closed below.
	KEY=/keys/module-signing.pem
	if [ ! -e "$KEY" ]; then
		echo "ERROR: module signing key not exposed at $KEY (builder key configuration?)" >&2
		return 1
	fi
	if [ ! -r "$KEY" ]; then
		echo "ERROR: module signing key exposed but unreadable at $KEY (UID ACL missing on the host key? builds must never go unsigned)" >&2
		return 1
	fi
	export TAR_OPTIONS=--no-same-owner

	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE.
	KBALL="$RECIPE_DIR/files/linux-${kernel_version}.tar.xz"
	[ -f "$KBALL" ] || KBALL="$RECIPE_DIR/files/linux-${kernel_version}.tar.gz"
	if [ -f "$KBALL" ]; then
		echo "$sha256  $KBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local linux-${kernel_version}.tar.{xz,gz} and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		KBALL=$SOURCE_ARCHIVE
	fi
	mkdir -p "$SRC/linux-${kernel_version}"
	tar --no-same-owner -C "$SRC/linux-${kernel_version}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${kernel_version}"

	patch -Np1 -i "$RECIPE_DIR/files/x86-64-v3.patch"
	cp "$RECIPE_DIR/files/config-${kernel_version}-akadata" "$SRC/linux-${kernel_version}/.config"
	mkdir -p "$SRC/linux-${kernel_version}/certs/regdb"
	cp "$RECIPE_DIR/files/saphira-regdb.x509" "$SRC/linux-${kernel_version}/certs/regdb/saphira-regdb.x509"
	cp "$KEY" "$SRC/linux-${kernel_version}/certs/module-signing.pem"
	chmod 600 "$SRC/linux-${kernel_version}/certs/module-signing.pem"

	make olddefconfig
	# No-initramfs builtin policy: Saphira ships without an initramfs, so
	# every root/console/network driver must be =y, not =m. olddefconfig
	# silently resolves new and changed symbols to defaults, which is how
	# a required builtin would be lost without anyone touching the config.
	# This gate fails the build before the compile, not after publication.
	. "$RECIPE_DIR/files/check-no-initramfs-builtins.sh"
	check_no_initramfs_builtins "$SRC/linux-${kernel_version}/.config" "$kernel_version"
	make -j${JOBS:-$(nproc)}

}

recipe_install()
{
	# INSTALL_MOD_STRIP=1 is the kernel's own module-install stripping
	# mechanism, used here as a defence in depth behind the config-level
	# debug policy. It is not redundant: the config asserts no DWARF is
	# generated at all, while this guarantees no debug payload reaches a
	# runtime .ko even if some future config or toolchain reintroduces it.
	# Previously the package was assembled with a bare modules_install, so
	# whatever the build produced shipped verbatim -- which is how 218
	# modules totalling 745 MiB were published in r7-r9.
	make INSTALL_MOD_PATH="$PKGDEST" INSTALL_MOD_STRIP=1 modules_install
	install -d "$PKGDEST/boot"
	install -m 644 "$SRC/linux-${kernel_version}/arch/x86/boot/bzImage" "$PKGDEST/boot/vmlinuz-${kernel_version}-akadata"
	install -m 644 "$SRC/linux-${kernel_version}/System.map" "$PKGDEST/boot/System.map-${kernel_version}-akadata"
	install -m 644 "$SRC/linux-${kernel_version}/.config" "$PKGDEST/boot/config-${kernel_version}-akadata"
	# saphira-kernel is a RUNTIME package. Upstream modules_install bakes the
	# absolute build-tree path into lib/modules/<release>/{build,source};
	# constructor state under /build must never leak into an installed
	# filesystem. This package used to resolve that by SHIPPING the prepared
	# tree at /usr/src/linux-<pkgver>-saphira and pointing build at it, which
	# put 1648 MiB and 77,655 files of kernel source into a runtime APK and
	# grew every installed rootfs to roughly 3 GiB.
	#
	# It does not: no /usr/src, no prepared tree, no build/source symlink --
	# not even dangling, because a link that can only dangle is a trap for
	# whoever debugs the next thing. An out-of-tree module build is a
	# BUILD-TIME concern and belongs to the builder, which prepares its own
	# tree from the vendored tarball and config. No replacement kernel-build
	# package is introduced here either: a public runtime distribution must
	# not become a build workstation by accident.
	#
	# KREL is the true kernel release (differs from pkgver on -rc lines);
	# depmod and the module dir both use it.
	. "$RECIPE_DIR/files/install-kernel-layout.sh"
	KREL=$(kernel_layout_release "$SRC/linux-${kernel_version}")
	# Upstream modules_install itself creates lib/modules/<rel>/build and
	# lib/modules/<rel>/source as symlinks to the absolute build tree under
	# /build. Deleting them is not cosmetic: they are constructor state
	# pointing outside the package, and /build does not exist on an
	# installed system. They are removed here rather than repointed, because
	# there is no legitimate runtime target for them and a link that can
	# only dangle misleads whoever debugs the next thing. check_module_layout
	# asserts their absence, so this cannot be undone by accident.
	rm -f "$PKGDEST/lib/modules/$KREL/build" "$PKGDEST/lib/modules/$KREL/source"
	check_module_layout "$PKGDEST" "$KREL" "$KREL"
	depmod -b "$PKGDEST" $KREL
	# Declared maintainer hooks: regenerate the boot configuration after
	# the /boot payload lands. Both install and upgrade need it -- an
	# upgrade is exactly the case that used to leave the old kernel in
	# the menu. makepkg embeds these into the package lifecycle scripts
	# and strips this declaration from the payload, so the generated
	# script is the only shipped copy.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
}

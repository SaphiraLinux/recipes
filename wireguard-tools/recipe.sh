#!/bin/sh
pkgname=wireguard-tools
pkgver=1.0.20260223
pkgrel=5
# r3: /etc/wireguard ships 0700 (homer recon: Arch carries 0700;
# the directory will hold private keys, so list access stays
# root-only even though key files themselves are 0600).
# (Adopted from hotfix/var-packaging-bug-var-run-isnot-run; enforced
# explicitly below alongside the pre-existing existence proof.)
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='WireGuard userspace tools (wg, wg-quick)'
license='GPL-2.0-only'
origin=wireguard-tools
repo=saphira
url=https://www.wireguard.com/
wireguard_tools_sha256=587db136e52a53999bd58df8626137b2600db90909a4020b0f7c8b356ac6799b
# wg-quick is a shell script, so this package's runtime closure is the
# commands that script executes, not a DT_NEEDED chain. Each entry below
# was read out of the vendored src/wg-quick/linux.bash for this version:
#
#   bash      - wg-quick's own #!/bin/bash shebang.
#   iproute2  - `ip link add dev ... type wireguard` (linux.bash:91) and
#               every address/route/rule operation after it.
#   nftables  - add_default() installs the fwmark + policy-routing rules
#               with `nft -f` when nft is present (linux.bash:242-243); with
#               no nft it falls back to iptables-restore, and Saphira
#               packages no iptables, so without nft the IPv4/IPv6 `up`
#               aborts at linux.bash:245.
#   procps-ng - the src_valid_mark sysctl on the IPv4 path
#               (linux.bash:241). Under `set -e` a missing sysctl takes
#               the whole `up` down, not merely the rule.
#   coreutils - readlink -f (linux.bash:46), stat -c (linux.bash:47) and
#               sort, all of which wg-quick calls unconditionally.
#
# Deliberately NOT a dependency: resolvconf. wg-quick calls it only when a
# configuration carries DNS= (linux.bash:155-161), Saphira packages no
# resolvconf provider, and inventing one is out of scope here. A config
# with DNS= therefore cannot be brought up until one exists; a config
# without it is unaffected.
#
# Not a service identity: wg-quick programs the kernel and its own
# fwmark table and must run as root (CAP_NET_ADMIN), so there is no
# accounts.d fragment for this package.
depends="bash coreutils iproute2 nftables procps-ng"
makedepends="saphira-linux-uapi-headers gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/wireguard-tools-v1.0.20260223.tar.xz"
	cd "$SRC"
	echo "$wireguard_tools_sha256  $RECIPE_DIR/files/wireguard-tools-v1.0.20260223.tar.xz" | sha256sum -c -
	# The userspace/kernel interface is pure netlink on every kernel this
	# distribution boots (>= 5.6), so upstream's RUNSTATEDIR (which only
	# feeds the dead pre-5.6 $RUNSTATEDIR/wireguard/*.sock path in
	# src/ipc-uapi-unix.h) is left at its default and is not compiled to
	# /run the way the old-gen recipe and /cports do. On those systems
	# /var/run is a symlink into /run; here the two are distinct
	# directories, so the flag would be a guess about kernel behaviour
	# with no effect, taken from a filesystem layout Saphira rejects.
	make -C src -j${JOBS:-$(nproc)} \
		WITH_BASHCOMPLETION=yes WITH_SYSTEMDUNITS=no \
		WITH_WGQUICK=yes
}
recipe_install() {
	# WITH_SYSTEMDUNITS stays no: upstream's install rule resolves
	# SYSTEMDUNITDIR from `pkg-config --variable=systemdsystemunitdir
	# systemd`, which in a build root can name a build-root prefix rather
	# than the destination. The units are installed below to the literal
	# destination path instead.
	make -C "$SRC/src" install \
		WITH_BASHCOMPLETION=yes WITH_SYSTEMDUNITS=no \
		WITH_WGQUICK=yes PREFIX=/usr DESTDIR="$PKGDEST"
	# Dual-init policy: BOTH definitions ship unconditionally; neither is
	# enabled or started at install.
	#
	# systemd: upstream's own units, taken from the verified archive
	# rather than re-typed, so they cannot drift from the source. It is a
	# TEMPLATE unit (wg-quick@.service) plus wg-quick.target, which every
	# instance is PartOf and Before=; wg-quick.target is not decoration,
	# it is the target the template orders against.
	install -d -m 0755 "$PKGDEST/usr/lib/systemd/system"
	install -m 0644 "$SRC/src/systemd/wg-quick@.service" \
		"$PKGDEST/usr/lib/systemd/system/wg-quick@.service"
	install -m 0644 "$SRC/src/systemd/wg-quick.target" \
		"$PKGDEST/usr/lib/systemd/system/wg-quick.target"
	# wg-quick resolves ip(8)/nft(8)/coreutils through PATH at runtime, but
	# upstream's unit sets no PATH, so the service inherits systemd's
	# compiled-in default and ip is not guaranteed to be found: /sbin/ip is
	# /sbin/ip here, not /usr/sbin, because Saphira is non-usrmerge while
	# wg-quick is /usr/bin/wg-quick. A drop-in states the PATH instead of
	# inheriting it, and keeps the unit byte-identical to the archive.
	install -d -m 0755 "$PKGDEST/usr/lib/systemd/system/wg-quick@.service.d"
	install -m 0644 "$RECIPE_DIR/files/wg-quick-path.conf" \
		"$PKGDEST/usr/lib/systemd/system/wg-quick@.service.d/10-path.conf"
	# openrc: upstream ships no init script at all, so files/wg-quick.initd
	# is the Saphira counterpart, instance-aware for the same reason the
	# unit is a template.
	install -d -m 0755 "$PKGDEST/etc/init.d"
	install -m 0755 "$RECIPE_DIR/files/wg-quick.initd" \
		"$PKGDEST/etc/init.d/wg-quick"
	# Fail closed at build time rather than at boot. daemon-init.sh sees
	# both formats from the literal paths above, and the payload is proven
	# here, so a unit that names a path this recipe does not install is
	# caught before publication.
	[ -e "$PKGDEST/etc/init.d/wg-quick" ] || { echo "ERROR: wireguard-tools payload is missing etc/init.d/wg-quick" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/wg-quick@.service" ] || { echo "ERROR: wireguard-tools payload is missing usr/lib/systemd/system/wg-quick@.service" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/wg-quick.target" ] || { echo "ERROR: wireguard-tools payload is missing usr/lib/systemd/system/wg-quick.target" >&2; return 1; }
	# Fail closed on the PATH drop-in. Without a PATH containing /sbin the
	# unit starts, finds no ip(8), and exits 127 at runtime rather than at
	# boot, which is exactly the failure this exists to prevent.
	dropin="$PKGDEST/usr/lib/systemd/system/wg-quick@.service.d/10-path.conf"
	[ -f "$dropin" ] || { echo "ERROR: wireguard-tools payload is missing the wg-quick PATH drop-in" >&2; return 1; }
	grep -q '^Environment=PATH=.*:/sbin:' "$dropin" || { echo "ERROR: the wg-quick PATH drop-in does not put /sbin on PATH" >&2; return 1; }
	[ -x "$PKGDEST/usr/bin/wg" ] || { echo "ERROR: wireguard-tools payload is missing usr/bin/wg" >&2; return 1; }
	[ -x "$PKGDEST/usr/bin/wg-quick" ] || { echo "ERROR: wireguard-tools payload is missing usr/bin/wg-quick" >&2; return 1; }
	# Every executable the shipped definitions name must be one this
	# payload owns, in the tree it owns it in (non-usrmerge policy). The
	# whitelist is the whole contract: wg and wg-quick are installed by
	# PREFIX=/usr into /usr/bin, and bash is installed by the build seed
	# into /bin (bash is --bindir=/bin, so /usr/bin/bash does not exist).
	# Anything else appearing in the unit is a NEW runtime dependency that
	# must be declared and reasoned about here, not discovered at boot, so
	# the build refuses it instead of shipping a unit that cannot run.
	# This is asserted on the built payload rather than on a copy in
	# files/, which is why non-usrmerge.sh never sees this unit.
	unexpected=$(grep -oE '/(usr/)?(s?bin)/[A-Za-z0-9_.@-]+' \
		"$PKGDEST/usr/lib/systemd/system/wg-quick@.service" |
		grep -vx -e /usr/bin/wg-quick -e /usr/bin/wg -e /bin/bash || true)
	[ -z "$unexpected" ] || {
		echo "ERROR: wg-quick@.service invokes executables this package does not install: $unexpected" >&2
		return 1
	}
	# The OpenRC counterpart runs wg-quick and nothing else privileged.
	grep -q '^wgquick=/usr/bin/wg-quick$' "$PKGDEST/etc/init.d/wg-quick" || {
		echo "ERROR: wg-quick.initd does not drive /usr/bin/wg-quick" >&2
		return 1
	}
	# /etc/wireguard comes from upstream's install rule at mode 0700: it
	# holds private keys, and wg-quick refuses (with a warning) to bring
	# up a world-accessible configuration. Enforce the mode explicitly
	# (r3: root-only listing on top of 0600 keys) rather than trusting
	# the install rule alone, then prove the result.
	install -d -m 0700 "$PKGDEST/etc/wireguard"
	[ -d "$PKGDEST/etc/wireguard" ] || { echo "ERROR: wireguard-tools payload is missing etc/wireguard" >&2; return 1; }
}

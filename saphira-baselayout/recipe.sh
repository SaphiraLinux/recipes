#!/bin/sh

pkgname=saphira-baselayout
pkgver=0.1
pkgrel=20
# r20: reconciler failure semantics (live Egg incident: orchestrated
# ensure-fhs died usage on `--root ""` and the deaths were counted
# as drift inside a success-style summary). --root accepts an empty
# value as live in ensure-fhs; check-mode execution errors exit 2
# (drift stays 1) in ensure-fhs/ensure-identity.sh; check-mode
# identity resolution falls back to the fragment index for
# declared-but-absent users/groups (audit must not die on what
# apply would create). Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira filesystem skeleton and platform tools (init-system neutral)"
license="BUSL-1.1"
replaces="akadata-baselayout"
origin=saphira-baselayout
repo=main
url=https://saphira.vm2.uk/

depends=""

makedepends=""

# r19: permissions V1 foundation (saphira-permissions slice):
# ensure-fhs gains [--root PATH] (offline recovery against a mounted
# root, honouring $SAPHIRA_ENSURE_ROOT) and --check (drift report,
# exit 1 on drift, zero mutation); ensure-identity.sh gains --check
# (same contract, including legacy-migration and database-mode
# reporting); both honour administrator overrides from
# /etc/saphira/permissions/override.d via the new shared
# permissions-override.sh library (ignore/pin/pin-cap, exact-path
# only, never additive). Generated package callers are unchanged
# (no flags), so install/upgrade behaviour is byte-identical.
# Payload change, revision bumps.
# r18: virgin-assembly fixes (canonical base rebuild ran r17's new
# post-install in a root with no /bin/sh and no sed): ensure-fhs uses
# POSIX expansion instead of sed, and chowns root by numeric 0:0 (no
# NSS lookup). Payload change, revision bumps.
# r17: ensure-identity.sh tolerates the sysusers stanza (mechanism
# selector for the generated caller, not an identity declaration):
# every helper pass skips it with arity enforced, so sysusers-native
# fragments (systemd r9+) converge instead of failing post-upgrade
# with "unknown stanza". Payload change, revision bumps.
# r16: FHS invariant slice (hotfix/var-packaging-bug-var-run-isnot-run):
# ships real /var/run AND /run (separate real directories, never
# aliases), the Saphira-native ensure-fhs reconciler, the baselayout
# global fhs.d fragment (historical /var/run symlink, /usr/var
# residue, core dirs), and the saphira-fhs-converge boot service
# (both inits, runs before ordinary services). Baselayout's own
# install/upgrade callers for its fragment need the makepkg fhs.d
# support from the same branch: build only after that slice lands.
# r15: ensure-identity.sh auto-repairs exact legacy mappings in
# place (locked, backed up, post-verified), so apk fix/upgrade
# self-heal recognised drift with no manual reconcile step;
# saphira-identity reconcile's user-side target-GID check aligned
# to the declared primary group (same rule both tools).
# r5: accounts.tsv gained the proxyto:proxyto 19 reservation after r4
# was cut (hatchling's r4 predates it, so promote-repo would publish
# stale bytes under a live NVR - payload changed, revision bumps).
# r10: ships usr/libexec/saphira/ensure-identity.sh, the additive live
# account reconciler called from makepkg-generated package scripts.
# r0 of the saphira-baselayout name (continues akadata-baselayout r1):
# r0: akadata-baselayout renamed to saphira-baselayout (Genesis rebrand).
# Payload paths and env prefixes migrated (sbin/saphira-firstboot,
# /usr/libexec/saphira, /var/lib/saphira-firstboot, SAPHIRA_FIRSTBOOT_*).
# Previous restructure: every OpenRC-specific path moved out to the openrc
# package (halt/poweroff/reboot/openrc-shutdown, and the boot services
# saphira-boot-ok/net-online/network with conf.d/network).  Installing
# openrc on top of this layout reproduces the v0.1 behaviour; removing
# openrc leaves zero OpenRC traces behind.  The systemd variant needs no
# separate baselayout fork: this one is neutral.  saphira-base-abi stays
# untouched; it tracks ABI, not init systems.

recipe_build()
{
	:
}

recipe_install()
{
	install -d -m 0755 \
		"$PKGDEST/etc/conf.d" "$PKGDEST/etc/cron.daily" \
		"$PKGDEST/etc/cron.hourly" "$PKGDEST/etc/cron.monthly" \
		"$PKGDEST/etc/cron.weekly" "$PKGDEST/etc/default" \
		"$PKGDEST/etc/profile.d" "$PKGDEST/etc/skel" \
		"$PKGDEST/etc/network.d" "$PKGDEST/sbin" \
		"$PKGDEST/usr/libexec/saphira" "$PKGDEST/usr/share/saphira" \
		"$PKGDEST/usr/share/saphira/fhs.d" \
		"$PKGDEST/var/empty" "$PKGDEST/var/lib/saphira-firstboot" \
		"$PKGDEST/var/spool/mail" \
		"$PKGDEST/var/run" "$PKGDEST/run"
	install -m 0644 "$RECIPE_DIR/files/inittab" "$PKGDEST/etc/inittab"
	install -m 0644 "$RECIPE_DIR/files/profile" "$PKGDEST/etc/profile"
	install -m 0644 "$RECIPE_DIR/files/network.conf" \
		"$PKGDEST/etc/network.conf"
	install -m 0644 "$RECIPE_DIR/files/default-grub" \
		"$PKGDEST/etc/default/grub"
	for example in 10-eth0.conf.example 20-eth1.conf.example; do
		printf '# Example %s interface configuration.\n# INTERFACE=eth0\n# ADDRESS=192.168.0.10/24\n# GATEWAY=192.168.0.1\n' \
			"${example%%-*}" > "$PKGDEST/etc/network.d/$example"
	done
	install -m 0644 /dev/null "$PKGDEST/etc/skel/.bashrc"
	printf 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin\n' > \
		"$PKGDEST/etc/skel/.profile"
	install -m 0755 "$RECIPE_DIR/files/saphira-firstboot" \
		"$PKGDEST/sbin/saphira-firstboot"
	install -m 0755 "$RECIPE_DIR/files/saphira-network-config" \
		"$PKGDEST/sbin/saphira-network-config"
	install -m 0755 "$RECIPE_DIR/files/sbin/saphira-identity" \
		"$PKGDEST/sbin/saphira-identity"
	install -m 0755 "$RECIPE_DIR/files/installkernel" \
		"$PKGDEST/sbin/installkernel"
	install -m 0755 "$RECIPE_DIR/files/nologin" "$PKGDEST/sbin/nologin"
	install -m 0755 "$RECIPE_DIR/files/libexec/apply-accounts.sh" \
		"$PKGDEST/usr/libexec/saphira/apply-accounts.sh"
	install -m 0755 "$RECIPE_DIR/files/libexec/ensure-identity.sh" \
		"$PKGDEST/usr/libexec/saphira/ensure-identity.sh"
install -m 0755 "$RECIPE_DIR/files/libexec/ensure-fhs" \
	"$PKGDEST/usr/libexec/saphira/ensure-fhs"
# Shared administrator-override lookup, sourced by ensure-identity.sh,
# ensure-fhs, and the saphira-permissions tools (read-only library:
# never executed directly).
install -m 0644 "$RECIPE_DIR/files/libexec/permissions-override.sh" \
	"$PKGDEST/usr/libexec/saphira/permissions-override.sh"
	install -m 0644 "$RECIPE_DIR/files/fhs.d/saphira-baselayout" \
		"$PKGDEST/usr/share/saphira/fhs.d/saphira-baselayout"
	# Boot convergence (both inits, unconditional like any service
	# package): the historical alias swap runs here, never live.
	install -D -m 0755 "$RECIPE_DIR/files/saphira-fhs-converge.initd" \
		"$PKGDEST/etc/init.d/saphira-fhs-converge"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-fhs-converge.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-fhs-converge.service"
	install -m 0755 "$RECIPE_DIR/files/libexec/apply-network.sh" \
		"$PKGDEST/usr/libexec/saphira/apply-network.sh"
	install -m 0644 "$RECIPE_DIR/files/accounts.tsv" \
		"$PKGDEST/usr/share/saphira/accounts.tsv"
	# Seeds consumed by apply-accounts.sh when the historical
	# stage4 source tree is absent (installer targets).
	install -m 0644 "$RECIPE_DIR/files/root.profile" \
		"$PKGDEST/usr/share/saphira/root.profile"
	install -m 0644 "$RECIPE_DIR/files/00-loopback.conf" \
		"$PKGDEST/usr/share/saphira/00-loopback.conf"
	install -m 0755 "$RECIPE_DIR/files/libexec/configure-stage4-grub" \
		"$PKGDEST/usr/libexec/saphira/configure-stage4-grub"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-baselayout/LICENSE"
}

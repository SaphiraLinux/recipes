#!/bin/sh

pkgname=saphira-baselayout
pkgver=0.1
pkgrel=65
# r62: backfilled identity registry (86 packaged/systemd rows; existing
# rows byte-identical) plus firstboot arming on the apk skeleton's empty
# root hash (0.2.2 images shipped locked-root with no marker and no
# wizard path). Payload change (seed + helper).
# r61: plugdev seed group 164 -> 177 (164 belongs to the published
# keystone service identity, claimed before the seed row existed;
# the seed vacates per its own rule. udev rules name the group, so
# the move is free). Unblocks publication (repo gate refused the
# GID collision on every transaction). Payload change (seed).
# r60: FHS converge ordering fix + plugdev group:
# the unit no longer orders against tmpfiles-setup-dev (upstream runs
# it before local-fs-pre: cycle + udevd dragged behind local mounts,
# Minimer boot proof) while the full tmpfiles-setup stage stays
# ordered after; plugdev:164 joins the device-owner seed block so
# libjaylink udev rules stop warning and J-Link works for members.
# r59: sysusers three-phase replay + utmp:20/empower:21 seed (2026-10-23):
# groups resolve before users in dependency order; missing automatic
# identities fail naming the manifest; name-form GIDs resolve via
# lookup. Payload change (reconciler + seed).
# r58: firstboot wizard fixes (2026-10-23, both proven in a VM boot):
# empty unfinished-steps array initialized (=() — the all-success path
# died at the final report with "unbound variable"); empty DNS choice
# resolves to the advertised default before calling dns-provider
# (raw "" failed with "unknown DNS provider"). Payload change.
# r57: sysusers UID[:GID] replay (2026-10-23): upstream root 0:0 and
# nobody 65534:65534 lines converge instead of skipping; divergent
# GIDs resolve against declared groups, undeclared GIDs and malformed
# IDs fail closed. Payload change (reconciler).
# r56: systemd graph fixes (2026-10-23): Environment= moved to
# [Service] (it was ignored in [Unit], so the wizard never saw its
# at-boot marker); firstboot drops the redundant cross-transaction
# After=fhs-converge edge (transaction order already separates them;
# the edge is the reported-cycle shape). Payload change (unit).
# r55: remove the r21 init= override from default-grub (SEV1 architectural
# correction 2026-10-22: the r21 "kernel falls back, mixed fleet is safe"
# premise is false - an explicit init= never falls back and a nonexistent
# path panics, proven by the Egg boot failure that reached a live grub.cfg
# through the kernel upgrade hook. The bootloader never names the init
# implementation; /sbin/init is the sole canonical PID 1 entry point).
# Payload change (default-grub conffile).
# r54: systemd PATH drop-in sets DefaultEnvironment as well as
# ManagerEnvironment (proven on Minimer: ManagerEnvironment alone
# never reaches services, leaving daemons without /sbin:/bin;
# mariadb/rabbitmq failed boot on missing chown/uname/readlink).
# r53: restore the original UID/GID rule in ensure-identity.sh
# (0..999 creatable, 1000+ refused; tier ceilings and notices
# removed; collision/conflict and safe-reconciliation paths
# untouched) + document the user-line supplementary field. The r52
# shell/PATH payload is unchanged.
# r52: shell foundations (Saphira PATH policy + interactive defaults):
# canonical PATH order in profile/root.profile, new /etc/bashrc
# (root-aware prompt, history, completion hook, aliases) with skel
# thinned to wire it in, systemd ManagerEnvironment PATH drop-in
# (this systemd build omits /sbin:/bin from its compiled default),
# firstboot provisions home dotfiles only when absent.
# r51: supplementary-groups grammar in ensure-identity.sh ONLY
# (fragment `user` 7th field, additive memberships, conservative
# removal). Verified: the entire installed-vs-tree delta is this
# grammar (firstboot, accounts.tsv, ensure-fhs identical). Unblocks
# the libvirt qemu:kvm membership; no behavior change for existing
# fragments (6-field lines parse identically).
# r50: the completion rule contradicted itself. commit_completion runs
# BEFORE the network apply, but apply-network.sh refused any state
# where completed exists - so every post-commit network apply failed,
# the written config was rolled back, and committed machines came up
# with loopback only. The guard now admits completed plus a live
# transaction (active) and still refuses a stale completed state with
# none, so a stale marker can never bypass it. Also: the interface
# count typo (${#interfaces[$(@)]}), the pending username deleted
# before the resume check could read it, and two bare post-commit
# validations that aborted the wizard under set -e - all recorded
# instead of fatal now. Proven by tests/firstboot-completion.sh and
# tests/firstboot-network-apply.sh (real helper, post-commit and
# failure paths).
# r49: an identity must not die reconciling its own home directory.
# The reconciler pasted its root onto every path, so a root of "/" made
# them "//etc/passwd" and "//var/lib/dhcpcd". A double-slashed path is
# implementation-defined and chown(1) rejects it with EINVAL, so an
# account declared with a home was CREATED and then the reconciliation
# died fixing that home - leaving the package uninstallable with an error
# that names a path the caller never wrote. Found while declaring the
# dhcpcd identity, which is the first fragment in the tree to exercise a
# home directory through the real image build path. Proven by
# saphira-packager/tests/accounts.sh.
# r48: one owner for the network configuration, and a completion rule
# that cannot strand a machine. Found by live BIOS/OpenRC acceptance:
# network setup was lost across a reboot and firstboot offered itself
# again on every boot afterwards.
#
# THE SPLIT. saphira-baselayout shipped its own older copy of
# saphira-network-config at /sbin; saphira-network ships the real one at
# /usr/sbin. firstboot applied through the /sbin copy while the boot
# service ran the /usr/sbin one. They disagreed about everything that
# matters: /etc/network.conf and /etc/network.d versus
# /etc/saphira-network.conf and /etc/saphira-network.d, and the /sbin
# copy had no notion of SLAAC at all - a mode the wizard itself offers.
# So a reasonable answer either failed the apply outright, or was written
# where the boot service reaches it only through its legacy fallback.
# That copy is deleted, apply-network.sh now runs the owning binary, and
# it writes into the owning directory. The legacy /etc/network.d keeps
# working for existing installs as the owner's documented fallback.
# Guarded by saphira-network/tests/network-config-ownership.sh, which
# also fails if a second copy is ever added quietly.
#
# THE COMPLETION RULE. The root password is the commit point. firstboot
# runs only until it is set, and setting it spends the marker
# permanently; nothing after that may re-arm it. The previous contract
# spent the marker only after EVERY step succeeded, which is exactly what
# turned one late failure into an unbreakable loop: the machine was told
# setup would run again, rebooted into setup, failed the same way, and
# had no network with which to be repaired. A commit point has to be a
# fact about the machine, not a summary of how the wizard's own steps
# went. So: set_password root spends the marker at once, entry self-heals
# a machine that has a root password with the marker still armed (spend it
# and leave, never re-prompt), and the administrator, network, DNS and
# repository steps run best-effort afterwards - retried at most twice,
# skippable with q or Ctrl-C, recorded and reported as an explicit list of
# what is not configured, with boot continuing either way.
# Proven by tests/firstboot-completion.sh.
#
# Also fixed a latent silent abort: `sed ... | head -1` under
# `set -euo pipefail` exits non-zero when sed cannot open the file, which
# under set -e killed the wizard outright on any root with no
# /etc/os-release - no message, no marker movement, just a stopped
# process. Reading an optional file must never be able to end the
# transaction.
# r47: firstboot completion contract, navigation, and target-neutral
# kernel arguments. Found by live BIOS/OpenRC acceptance.
# Completion: the wizard died part-way through a finished-looking run
# and the machine offered setup again on the next boot, because an
# unchecked failure in the window between confirmation and the end left
# the marker armed and said nothing. Now every post-confirmation step is
# required and named (require_step), a network activation failure
# aborts instead of being tolerated and then reported as complete, the
# marker is spent last and its removal verified, and any failure exits
# through transaction_failed, which states what broke and leaves the
# marker intact on purpose. The marker is now also checked BEFORE the
# completion record: an ordinary boot with the marker spent is a silent
# success, and the one inconsistent state (record present, marker
# present) is loud rather than a silent reconfigure. Proven by
# tests/firstboot-completion.sh.
# Navigation: q or Ctrl-C goes back one step at every menu and input -
# from a gateway or address back to its mode menu, from the IPv6
# question back to the IPv4 mode, from an interface back to the previous
# one. Ctrl-C no longer terminates the transaction: a mistaken Static
# selection is recoverable without a reboot. TERM/QUIT/TSTP still refuse
# to end a setup in progress, because those are a console competitor
# hanging up, not an operator changing their mind.
# Network order, as the live console test showed it: IPv4 first, then
# whether IPv6 is wanted at all, then the IPv6 mode. The IPv6 question
# has no default either - blank re-prompts - and "no" disables IPv6 for
# that interface. Revisiting an interface replaces its recorded answer
# instead of appending a duplicate to the summary.
# /etc/skel ships real .bashrc and .profile now; they were a zero-byte
# file and a one-line PATH, which is what a first-boot account inherits.
# install_shell_defaults tolerates their absence rather than aborting the
# transaction over a dotfile.
# Kernel arguments: systemd.imds=no is gone from the packaged
# GRUB_CMDLINE_LINUX, which is init-neutral; saphira-image adds it for
# SaphiraD targets only, next to systemd.getty_auto=0. An OpenRC kernel
# line carries no systemd-only arguments.
# r46: network policy for a server, and firstboot in the right place.
# saphira-firstboot must never infer DHCP from an empty answer. The
# per-interface prompt used to offer (d)HCP/(s)tatic/(k)eep with D as
# the default, so pressing Enter silently configured DHCP and a
# machine could decide its own address from whatever answered on the
# wire. IPv6 configuration is now presented before IPv4, as two
# explicit menus - IPv6 Static/SLAAC/DHCPv6/Disabled and IPv4
# Static/DHCP/Disabled - and neither has a default: an empty answer
# re-prompts, because the address mode is an operator decision and is
# never inferred. DHCP and DHCPv6 are explicit operator selections
# only; static addressing, SLAAC where selected, and disabled are
# equally valid choices. Choosing Static now requires a valid address
# (blank re-prompts instead of silently disabling the family), and
# Disabled is the only way to say "no address for this family".
# Disabled for both families means Saphira leaves that interface
# alone: no configuration file is written for it, so nothing ever
# reconfigures it. Every detected interface is offered configuration
# and every one appears in the summary, including the ones left
# unconfigured. The DNS prompt still preselects Quad9 and the final
# confirmation still defaults to Y: those are different classes of
# decision, not addressing choices.
# Ordering: firstboot no longer runs first in sysinit. It now runs in
# the boot runlevel, after the boot-level services that constitute
# essential boot and platform setup (modules and kernel state,
# filesystem work, seedrng for entropy, console encoding, the FHS
# convergence), so the wizard appears on a console that has finished
# booting rather than halfway through it - and, on a machine where
# interfaces are still being discovered, no longer races its own
# interface list. It still blocks its runlevel, so gettys, sshd and
# the network service start only after setup completes.
# dhcpcd remains installed as an optional capability and is never
# enabled or started merely because it is present; it runs only for an
# explicit DHCP or DHCPv6 selection, confined to the selected family,
# and never writes the resolver, so the DNS recorded here stays
# authoritative.
# r45: the kernel console is the VGA and only the VGA. The packaged
# GRUB_CMDLINE_LINUX listed "console=tty0 console=ttyS0,115200n8"; the
# kernel takes the LAST console= as the device /dev/console maps to, so
# /dev/console became ttyS0 - a serial port most Saphira machines do not
# have. Firstboot runs entirely on /dev/console (the openrc init script
# redirects stdin/stdout/stderr there, the systemd unit sets
# TTYPath=/dev/console), so on a machine with no serial hardware it had
# nowhere to show a prompt or read an answer: an unconfigured BIOS
# acceptance image booted straight past firstboot to the login prompt,
# with the failure invisible (getty clears the screen; agetty uses
# /dev/tty1, which is why login still worked). The r44 wizard itself was
# proven good by running it inside that image's root. Serial consoles
# remain supported for deployments that have one: add console=ttyS0 to
# the kernel line there, and the wizard's console-aware erase handling
# (serial '^H', VT '^?') applies as before. The boot menu terminals stay
# dual (grub ignores a terminal it cannot open; the VGA menu is proven).
# r44: firstboot console polish (single OpenRC BIOS acceptance pass).
# The wizard configures the erase character for the console actually
# attached (VT '^?', serial '^H' - the unconditional '^H' broke
# Backspace on VGA), clears the screen and presents a proper welcome
# screen (product from os-release, 60-column rules, bullet summary,
# "Press Enter to begin"), labels each phase with a heading, offers
# IPv6-as-well on the DHCP path, accepts a blank static gateway,
# shows DNS provider addresses in the choice, defaults the
# repository prompt to Enter, and closes with a full summary and a
# [Y/n] confirmation. Kernel console output is quieted for the
# interactive window (restored on exit) so nothing overwrites a
# prompt. Completion also mints SSH host keys (best-effort; sshd's
# own first start remains the safety net) and prints a clean
# handover. The OpenRC init script's marker check moved from
# start_pre (return 1 = failed service and a boot-log line on every
# boot) into start() as a silent success with a no-op stop(), so
# ordinary boots reach the login prompt with no firstboot chatter.
# r43: move device-owner groups to GIDs 157-163. The r40 picks
# (124-126, 132-135) collided with published repo packages (hostapd
# 124, breathgslb 126, qmail 132) and blocked publication: the repo
# gate refuses any GID claimed twice, and published packages do not
# move, so the seed vacates. New block verified free against the live
# reservations table (plus systemd sysusers pins avoided).
# r42: remove the firstboot GRUB/systemd boot-mode architecture (the r40
# dedicated saphira-firstboot.target + bootloader selection was an
# unrequested design: ONE normal boot path; firstboot is init-level).
# The systemd service now runs in the normal boot, condition-gated on
# the marker; the boot gate serializing operational services behind
# setup follows after graph inspection (never a second boot mode).
# The wizard's at-boot handover signal is now explicit env
# (SAPHIRA_FIRSTBOOT_AT_BOOT from the init script/service) instead of
# a kernel-cmdline probe; a missing marker is a plain exit, never a
# reboot (a reboot there would loop on the single boot path).
# r41: no serial getty, ever. Saphira generally has no serial hardware,
# so firstboot no longer creates a serial login prompt (release_console
# removed with both its call sites); VGA gettys cover login. This also
# removes the dev-ttyS0.device wait that timed out on hardware without
# the port. claim_console's stops stay as defensive no-ops.
# r40: firstboot UX + device groups + fhs/tmpfiles order + idempotent
# dhcpcd (legacy copy) + no-imds. (The dedicated saphira-firstboot.target
# + bootloader selection from this rev was removed in r42: unrequested
# second boot mode. The wizard UX, groups, ordering, dhcpcd, and imds
# work below are retained.) The wizard applies
# network via SIGHUP (no bus runs this early), enables (not starts)
# the serial getty, and hands off with a reboot into the normal boot.
# OpenRC keeps its strictly-ordered sysinit-first blocking start (no
# reboot needed there). The wizard also prints a product heading
# (PRETTY_NAME) before asking anything. New device-owner groups
# (cdrom, tape, dialout, kvm, render, sgx, clock) silence udev/tmpfiles
# "Unknown group" noise and fix node ownership (/dev/rtc0, /dev/kvm).
# fhs-converge runs Before both tmpfiles units (alias swap must precede
# population; the race failed first boots intermittently).
# saphira-network-config (legacy /sbin copy invoked by firstboot)
# gains the same idempotent dhcpcd_up helper as the current copy.
# r48 removed that copy outright: see the r48 note at the top.
# Default kernel cmdline gains systemd.imds=no (Saphira is not a cloud
# image; the auto-detecting IMDS generator otherwise logs a failed
# hwdb lookup on every boot).
# r39: order the wizard after vconsole-setup as well (it is pulled in
# beside the wizard and would otherwise print its completion line
# into the interactive session just as the first prompt appears;
# DefaultDependencies=no with no After=sysinit of its own, so no
# cycle, and After-without-Requires can never block setup).
# r38: exclusive-console firstboot ordering (both inits) + console
# erase setup. OpenRC: the wizard runs first in sysinit with a
# FOREGROUND blocking start() (keyword -timeout opts out of
# openrc-run's 60s SIGKILL, WAIT_TIMEOUT in openrc-run.c) instead of
# detached in boot, so no service output can interleave with the
# prompts; normal services start only after setup. systemd: the unit
# runs Before sysinit.target (DefaultDependencies=no, after udevd and
# networkd - both DefaultDependencies=no upstream, so cycle-free) for
# the same exclusivity; sshd/getty/sessions start only after setup.
# The wizard also establishes the console erase character (^H, what
# libvirt/virt-manager serial consoles send) instead of inheriting
# the kernel default ^?, which made every Backspace echo literally.
# r37: firstboot survival traps first (HUP ignored outright:
# a console competitor can hang up the session in the first
# milliseconds, before any later trap would be installed).
# r36: firstboot unit routes stdout/stderr to the console too
# (stdin alone left a blind wizard: prompts in the journal,
# input on the serial - proven deaf); no TTYVHangup.
# r35: tunnels report ARPHRD_ETHER too, so firstboot requires a real
# backing device link as well (erspan/gretap excluded, proven); a
# failed activation restores the previous stanza (or removes the new
# one) instead of leaving poison behind (both paths proven).
# r34: firstboot network activation is per-interface best-effort
# (warn + continue, accounts/identity still established) instead
# of aborting the whole run on one failed NIC.
# r33: firstboot enumerates ARPHRD_ETHER interfaces only (tunnel
# devices like erspan0 cannot be addressed and aborted the whole
# activation with 'Address not available' - proven on hardware).
# r32: firstboot creates the serial login prompt on completion
# (enable+start, both inits) instead of racing a pre-enabled getty
# for the same port; the image ships no serial getty anymore.
# r31: firstboot launch that survives service supervision -
# openrc-run SIGKILLs a foreground-blocking start() at timeout, and
# systemd oneshot defaults to a 90s start timeout, so the wizard now
# runs detached (setsid, console fds) with an instant-returning
# start(), TimeoutStartSec=infinity on the unit, and owns the console
# by stopping/restarting the serial getty around the session (a
# sharing getty provably steals input mid-wizard).
# r30: firstboot release readiness - the existing wizard repaired in
# place (no new package): /bin/bash shebang + self-sufficient PATH
# (both were merged-usr assumptions that broke first boot), getent
# replaced by local awk lookups, interface discovery with per-NIC
# DHCP/static/skip instead of hardcoded eth0, hatchling repo URL
# corrected to hatched, machine-id minted at completion, Wi-Fi
# offered only when its packages exist. New dual-init invocation
# services (marker-gated no-ops without it) enabled by the image.
# r29: self-sufficient PATH in ensure-fhs and ensure-identity.sh
# (same non-usrmerged reason: install callers and the systemd boot
# unit run with a bare PATH; ensure-fhs died with dirname-not-found
# on first boot, failing fhs-converge).
# r28: no staging path literally anywhere shipped (the r27 comment
# itself named the retired path and tripped the provenance gate).
# r27: retire Stage4 archaeology (configure-stage4-grub removed: no
# callers, staging path in guard; apply-accounts.sh drops the
# $ROOT/out/stage4/rootfs clause, installer target only). No staging
# path may appear in shipped tooling.
# r26: sysusers replay converges on reserved exact matches (systemd
# basic.conf re-declares g root 0; systemd-sysusers no-ops that live,
# so the offline replay logs it and moves on). Grants nothing: missing
# and redefined reserved identities still die in ensure_*. Proven by
# the 0.2.1 SaphiraD assembly, which could not complete without it.
# r25: ensure-fhs uid_of/gid_of read the target root's own database in
# all cases (the `getent | cut` empty-ROOT branch succeeded empty when
# getent was absent, masking the fallback and producing `chown 81:`
# failures - proven on dbus/polkit installs). No getent/id dependency.
# r24: merge line (r23 nomodeset-drop + r20 reconciler semantics + r16
# fhs.d machinery + r22 inittab split combined: the merged payload
# carries ensure-fhs, permissions-override.sh, the global fhs.d
# fragment, the converge service and the real /var/run+/run dirs,
# which published r23 does not ship - payload change, bumps).
# r23: drop nomodeset from default-grub (it blinds UEFI console: no
# efifb, i915 is a module with no initramfs; proven on minimer N100).
# Payload change (default-grub conffile).
# r21: default-grub names init=/usr/lib/systemd/systemd (262 merged layout
# has no /sbin/init; kernel falls back on 261, so mixed fleet is safe).
# r20: reconciler failure semantics (live Egg incident: orchestrated
# ensure-fhs died usage on `--root ""` and the deaths were counted
# as drift inside a success-style summary). --root accepts an empty
# value as live in ensure-fhs; check-mode execution errors exit 2
# (drift stays 1) in ensure-fhs/ensure-identity.sh; check-mode
# identity resolution falls back to the fragment index for
# declared-but-absent users/groups (audit must not die on what
# apply would create). Payload change, revision bumps.
# (r20 adopted from hotfix/var-packaging-bug-var-run-isnot-run; r24
# already outranks r20. Published r23 predates the merge, so the
# merged payload takes the next revision.)
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
# r22: /etc/inittab leaves baselayout (it was the last OpenRC-specific
# path still shipped here, so every systemd machine carried a stale
# OpenRC sysvinit table). Ownership moves to the openrc package, which
# ships the byte-identical stock file; apk ownership semantics then
# govern both directions with no transition hooks. Payload change.

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
	# NOTE (merge line): no /etc/inittab here. r22 moved inittab
	# ownership to the openrc package (byte-identical stock file);
	# installing it here too would dual-own /etc/inittab and trip
	# the repository ownership gate.
	install -m 0644 "$RECIPE_DIR/files/profile" "$PKGDEST/etc/profile"
	# System-wide interactive Bash defaults (sourced by /etc/skel/.bashrc;
	# existing home dotfiles are never rewritten to pick it up).
	install -m 0644 "$RECIPE_DIR/files/bashrc" "$PKGDEST/etc/bashrc"
	# systemd manager environment: this systemd build omits /sbin and
	# /bin from its compiled DefaultEnvironment (proven by daemons
	# failing bare-name helper lookups), so set the canonical PATH
	# centrally rather than per-unit workarounds in every package.
	install -D -m 0644 "$RECIPE_DIR/files/systemd/system.conf.d/10-saphira-path.conf" \
		"$PKGDEST/etc/systemd/system.conf.d/10-saphira-path.conf"
	install -m 0644 "$RECIPE_DIR/files/network.conf" \
		"$PKGDEST/etc/network.conf"
	# Base sysctl defaults (source-route lock per RFC 7126; applied
	# by the sysctl service at boot, both init systems).
	install -m 0644 "$RECIPE_DIR/files/sysctl.conf" \
		"$PKGDEST/etc/sysctl.conf"
	install -m 0644 "$RECIPE_DIR/files/default-grub" \
		"$PKGDEST/etc/default/grub"
	for example in 10-eth0.conf.example 20-eth1.conf.example; do
		printf '# Example %s interface configuration.\n# INTERFACE=eth0\n# ADDRESS=192.168.0.10/24\n# GATEWAY=192.168.0.1\n' \
			"${example%%-*}" > "$PKGDEST/etc/network.d/$example"
	done
	install -m 0644 "$RECIPE_DIR/files/skel.bashrc" "$PKGDEST/etc/skel/.bashrc"
	install -m 0644 "$RECIPE_DIR/files/skel.profile" "$PKGDEST/etc/skel/.profile"
	install -m 0755 "$RECIPE_DIR/files/saphira-firstboot" \
		"$PKGDEST/sbin/saphira-firstboot"
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
	# Firstboot invocation (both inits): the wizard runs only while
	# /etc/saphira-firstboot-required exists (assembly writes it when
	# root ships locked or with the apk skeleton's empty hash - both
	# are unprovisioned; a supplied --root-password spends it again);
	# without the marker both are no-ops, so the
	# image enables them unconditionally via prepare_init.
	install -D -m 0755 "$RECIPE_DIR/files/saphira-firstboot.initd" \
		"$PKGDEST/etc/init.d/saphira-firstboot"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-firstboot.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-firstboot.service"
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
	# configure-stage4-grub is retired with the generation-zero
	# bootstrap (no callers; its guard named a staging path) and
	# removed from the tree; git history retains it.
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-baselayout/LICENSE"
}

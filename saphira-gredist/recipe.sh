#!/bin/sh

# r10: move the gredist identity off 123, which is gopher's in the base
# seed; one package owns each declared identity. 123 -> 150. The identity first
# appears in r9, which was staged but never published, so no migration and no
# legacy sidecar.
pkgname=saphira-gredist
pkgver=0.1.0
pkgrel=11
# r5: /etc/saphira ships 0750 (homer recon: operator configs and
# key material live beneath it; the previous 0755 came from an
# install -D side effect, never a decision). Payload change, bumps.
# r4: documented stats path /run/saphira/gredist ->
# /var/run/saphira/gredist (C default define + man page). The define
# is currently unwired (stats go to the log); no directory is ever
# created or consumed, so no fhs.d fragment by rule
# (document-and-leave, unbound precedent). Payload change (man
# page), revision bumps.
# (r4/r5 adopted from hotfix/var-packaging-bug-var-run-isnot-run;
# r10 already outranks r5.)
# r11: merge line (man page carries both the r4 /var/run FILES entry
# and the r10 COUNTERS section; merged payload differs from r10).
# Payload change, bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Protocol 47/GRE distributor with HRW backend selection'
license='BUSL-1.1'
origin=saphira-gredist
repo=saphira
url=https://saphira.vm2.uk/
# Local source (no upstream, no git yet): payload lives in files/
# (C11 control service + gre-sink/gre-send lab tools, man page,
# example config, lab harness), all Saphira-original under BUSL-1.1.
# r2: license corrected MIT -> BUSL-1.1.
# r3: kernel reference files removed (protocol reference only, never
# part of the source); all remaining MIT headers switched to BUSL-1.1.
# r6: acceptance re-baseline. Payload is byte-identical in intent to the
# published r5 (which was produced from the unmerged branch
# hotfix/var-packaging-bug-var-run-isnot-run, commits 75a8cac + 26569e2 and
# never passed the build queue's INSTALL stage). r6 exists solely to prove
# today's tree and packager can reproduce this same implementation through
# the normal build -> PASS -> publish path. Carries r4's /var/run stats-path
# documentation (the define is still unwired) and r5's /etc/saphira 0750.
# No C logic changes in r6. See acceptance/RESULTS.md.
# r7: the measured r5/r6 acceptance defects, all fixed together because each is
# independently provable by acceptance/tests/regress.sh and the same three-node
# harness run, and none of them touches the privilege model:
#   - no shell anywhere: the nft placeholder is deleted outright (it only ever
#     created empty tables that were never cleaned up, and was the daemon's
#     sole use of CAP_NET_ADMIN and of system()), and the service name derived
#     from a -c path is now validated exactly as strictly as one given
#     positionally. The -c basename previously reached
#     system("nft list table inet saphira_gredist_%s ...") and was executed by
#     /bin/sh as root before any socket was opened.
#   - HRW score no longer mixes in the backend's array index, so it depends on
#     backend identity alone. A bare config reorder used to remap 32 of 56
#     flows; regress.sh now requires 200/200 stable across three orderings.
#   - IP_HDRINCL removed from the lazy send path, which lost every packet and
#     misreported it as queue pressure.
#   - INV-1: the dst-mismatch drop is now counted (not_for_us), oversized is
#     counted once rather than twice, the IPv6 headerless fallback - which
#     forced the destination check to pass and could forward an IP header as
#     tunnel payload - is removed so an unparseable packet fails closed, IPv6
#     fragments are classified as fragments, and every counter appears in the
#     SIGUSR1 dump.
# Docs corrected: the nft fast path claim is removed, C13's stability claim now
# holds as written, /var/run/saphira/gredist is no longer documented (it was
# never created), and "forwarded" is defined as accepted-by-kernel.
# r8: health probing is no longer synchronous with the event loop. Each probe is
# a detached child; the loop reaps finished probes on every pass and SIGKILLs
# overran ones, reaping them on a later pass rather than blocking. Measured on
# the old code: one dead backend cost ~1.03 s of deafness and three cost
# ~5.5 s - longer than the 2 s health interval itself, so the distributor went
# offline while its own health checking ran. Cadence (2 s), thresholds (2 fail
# to down, 2 successes to up) and the transition log lines are unchanged, so
# health convergence is identical; only the waiting moved. In-flight probes
# shorten the poll timeout to 50 ms so results are collected promptly, and are
# cancelled on SIGHUP reload (the backend array is replaced, so an in-flight
# index would name a different backend) and on shutdown.
# Not in r8 (measured, fix designed, deferred to r9): the SIGHUP frontend
# rebind together with the in-daemon privilege drop. The packager INSTALL-stage
# defect that keeps every gredist revision out of the repository is a separate
# build-system blocker and is deliberately untouched here. See
# acceptance/RESULTS.md sections 6 and 9.
# r9: SIGHUP can no longer silently blackhole traffic, and the daemon runs as
# `gredist` for steady state.
#   - The receive socket is no longer bound. A raw socket can be bound exactly
#     once, which baked the configured frontend into the socket for the life of
#     the process: on SIGHUP with a changed frontend= the config was replaced,
#     the socket was not, and the daemon kept receiving only the old address
#     while logging "reloaded N backends" with no error - measured, a packet to
#     the new address moved no counter at all. socket() needs CAP_NET_RAW so
#     rebinding is impossible after the privilege drop, while bind() does not
#     need it. Neither helps alone, so the socket stays unbound and the
#     frontend is enforced per packet in userspace: a frontend change is a pure
#     config change effective on the next packet, and can now change family too.
#     Non-frontend GRE is now read and rejected here rather than never arriving;
#     it is counted in not_for_us.
#   - The daemon creates its sockets, then drops to the accounts.d `gredist`
#     identity (setgroups to one group, setgid, setuid, then proves setuid(0)
#     fails) and runs the event loop unprivileged. Measured first: sendto on the
#     pre-opened socket, bind, and the forked ICMP probe all work unprivileged;
#     only socket() needs CAP_NET_RAW. No privileged supervisor and no setcap,
#     which the payload could not carry anyway (no xattr channel).
#   - Startup verifies the config is still re-readable after the drop and exits
#     non-zero naming the chgrp, instead of starting unable to reload.
#   - Carries the accounts.d identity fragment; /etc/saphira stays 0750
#     root:root, so relaxing it is left as an explicit operator decision.

depends="iputils"
makedepends="
	gcc
	make
"
subpackages="$pkgname-doc"

recipe_build()
{
	# Local source builds out-of-tree so files/ stays pristine.
	rm -rf "$BUILDDIR/build"
	mkdir -p "$BUILDDIR/build"
	cp -r "$RECIPE_DIR/files/Makefile" "$RECIPE_DIR/files/src" "$BUILDDIR/build/"
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=x86-64-v3 ;;
		aarch64) march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-gredist: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -C "$BUILDDIR/build" -j${JOBS:-$(nproc)} CC=gcc ARCH="$march" PREFIX=/usr
	# Upstream tests need raw sockets, netns and OVS; the build
	# sandbox provides none, so they run on the lab, not here.
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/build/src/gredist" "$PKGDEST/usr/bin/gredist"
	install -D -m 0755 "$BUILDDIR/build/src/gre-sink" "$PKGDEST/usr/bin/gre-sink"
	install -D -m 0755 "$BUILDDIR/build/src/gre-send" "$PKGDEST/usr/bin/gre-send"
	# Shared config root: operator-owned, root-only listing. Carried from r5.
	# r9 note: gredist now runs as the `gredist` user (see the accounts.d
	# fragment), and 0750 root:root does not let that user traverse this
	# directory, so it cannot re-read its own configuration on SIGHUP. The
	# daemon checks this at startup and refuses to run rather than come up
	# deaf and reload-blind, naming the chgrp it needs. Widening the mode is
	# deliberately NOT done here: 0750 is a deliberate decision recorded in r5
	# and relaxing it is an operator's call, not a packaging side effect.
	# (Hotfix r5 line: this package owns the path via first-installer
	# file-gate rule - same 0750, same rationale.)
	install -d -m 0750 "$PKGDEST/etc/saphira"
	install -D -m 0644 "$RECIPE_DIR/files/man/gredist.1" \
		"$PKGDEST/usr/share/man/man1/gredist.1"
	install -D -m 0644 "$RECIPE_DIR/files/etc/saphira/gredist/example.conf" \
		"$PKGDEST/etc/saphira/gredist/example.conf"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-gredist/LICENSE"
	# Service identity, created and converged by the packager's accounts.d
	# reconciler (the same mechanism openssh and saphira-proxyto use).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-gredist" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-gredist"
	install -D -m 0755 "$RECIPE_DIR/files/tests/lab.sh" \
		"$PKGDEST/usr/share/saphira-gredist/lab.sh"
	install -D -m 0755 "$RECIPE_DIR/files/tests/run-tests.sh" \
		"$PKGDEST/usr/share/saphira-gredist/run-tests.sh"
}

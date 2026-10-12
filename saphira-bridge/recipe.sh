#!/bin/sh

# r2: move the bridge identity off 128, which is systemd-resolve's;
# one package owns each declared identity. 128 -> 149. Never published, so no
# migration and no legacy sidecar.
pkgname=saphira-bridge
pkgver=0.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Userspace Ethernet MAC-learning bridge for joining lab segments'
license='BUSL-1.1'
origin=saphira-bridge
repo=saphira
url=https://saphira.vm2.uk/
# Local source for now: the payload lives in files/ and mirrors the keeper
# repository keeper:/saphira-git-repo/saphira-bridge.git at dc82176,
# byte-for-byte across all 20 files. vendor=/sha256= are deliberately absent
# until a reachable public URL exists, rather than invented: a URL that cannot
# be fetched is the saphira-garden defect, and no build may depend on one.
#
# Business Change: new package. A small userspace Ethernet MAC-learning bridge.
# r1: initial publication.
#   - Joins two or more interfaces into one Layer 2 segment. Linux keeps
#     ownership of ARP, NDP, IP, routing and NAT and this daemon implements
#     none of them, so every stack on the segment behaves exactly as it would
#     behind a kernel bridge while the frames pass through a process that can
#     be read, counted and interrupted. It says so in its startup log.
#   - Learned from unicast sources only. A frame whose source is a group address
#     teaches the table nothing, because a table that takes a group's word for
#     who it speaks for can be fed a forged mapping for a legitimate host. The
#     frame still forwards; only the learning is refused, and that refusal is
#     counted separately from the drop counters.
#   - Fails closed. A frame addressed to the host that sent it is dropped rather
#     than reflected, because reflecting it is how a loop multiplies itself.
#     802.1D reserved traffic is neither learnt nor forwarded. VLAN tags are
#     refused and counted, not handled. Unknown keys in the configuration are
#     refused rather than ignored, so a typo cannot silently leave a port
#     unbridged. A duplicate port is refused because it would make "the port
#     this frame arrived from" ambiguous.
#   - The address table is bounded and ages. A table filled from addresses in
#     incoming frames is a memory exhaustion target, and without ageing a lab
#     that recreates its interfaces fills it with dead entries within a few
#     runs. When it is full, expired entries are reclaimed before any live one
#     is given up, and what is given up is counted as evicted.
#   - Deferred checksums are preserved, not recomputed. A sender with TX
#     checksum offload hands over a frame whose transport checksum is not yet
#     written; forwarding those bytes verbatim means the receiver discards them.
#     The kernel's own PACKET_VNET_HDR state - VIRTIO_NET_HDR_F_NEEDS_CSUM with
#     csum_start and csum_offset - is passed straight through, so the egress
#     path finishes the work and this daemon never parses IP. A frame whose
#     metadata cannot be carried is refused and counted, never forwarded
#     silently incomplete. Once a socket is in that mode the kernel reserves the
#     header on every send, so ordinary frames carry a zeroed one.
#   - VLAN tags are detected two ways, because this kernel strips the 802.1Q
#     bytes from the buffer while still reporting the tag in the auxdata. A tag
#     present in either place is refused.
#   - No loop prevention and no spanning tree. A source address seen on two
#     ports is counted and reported as a loop and deliberately not repaired,
#     because quietly healing a miswired segment hides the mistake that caused
#     it. THE TOPOLOGY MUST BE A TREE, and the man page says so.
#   - No VLAN support, no OpenFlow, no tunnels, no QoS, no bonding. This is a lab
#     instrument and not a network stack; OVS and saphira-network exist and do
#     more. It is not a second OVS.
#   - Service identity uid/gid 128, a fresh reservation immediately after
#     saphira-udpdist's 127. The packet sockets are opened before the drop
#     because promiscuous mode needs CAP_NET_ADMIN, and nothing needs privilege
#     afterwards; a reload that would need a new socket is refused rather than
#     attempted, so the daemon never needs the privilege back.
#   - No subpackages. A version-pinned subpackage cannot reach PASS through the
#     build daemon's INSTALL stage while that defect is unfixed, and
#     saphira-gredist is the proof; shipping without one keeps this package
#     installable.
depends=""
makedepends="
	gcc
	make
"

recipe_build()
{
	# Build out of tree so files/ stays pristine.
	rm -rf "$BUILDDIR/build"
	mkdir -p "$BUILDDIR/build"
	cp -r "$RECIPE_DIR/files/Makefile" "$RECIPE_DIR/files/src" "$BUILDDIR/build/"
	# Saphira baseline per target arch (x86-64-v3 today; extend here when new
	# SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=x86-64-v3 ;;
		aarch64) march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-bridge: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -C "$BUILDDIR/build" -j${JOBS:-$(nproc)} CC=gcc ARCH="$march" PREFIX=/usr
	# The suites need layer 2 access and network namespaces, which the build
	# sandbox provides neither of. They run on the lab and via
	# tests/regress.sh, not here.
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/build/src/saphira-bridge" \
		"$PKGDEST/usr/bin/saphira-bridge"
	install -D -m 0644 "$RECIPE_DIR/files/man/saphira-bridge.1" \
		"$PKGDEST/usr/share/man/man1/saphira-bridge.1"
	# Shared config root, matching the mode other Saphira daemons ship.
	install -d -m 0750 "$PKGDEST/etc/saphira"
	install -D -m 0644 \
		"$RECIPE_DIR/files/etc/saphira/saphira-bridge.example.conf" \
		"$PKGDEST/etc/saphira/saphira-bridge.example.conf"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-bridge/LICENSE"
	# Service identity (uid/gid 128), created and converged by the packager's
	# accounts.d reconciler, the same mechanism gredist, proxyto and
	# saphira-udpdist use.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-bridge" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-bridge"
	# The suites are installed for reference and are run from the source tree:
	# they build the daemon and their own probe on demand, so a copy in a
	# share directory is a record of what was proven, not a runnable one.
	install -D -m 0755 "$RECIPE_DIR/files/tests/regress.sh" \
		"$PKGDEST/usr/share/saphira/saphira-bridge/regress.sh"
	install -D -m 0755 "$RECIPE_DIR/files/tests/bridge-lab.sh" \
		"$PKGDEST/usr/share/saphira/saphira-bridge/bridge-lab.sh"
}

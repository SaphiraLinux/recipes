#!/bin/sh

pkgname=saphira-udpdist
pkgver=0.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Layer 4 UDP distributor with HRW selection and QUIC-LB routing'
license='BUSL-1.1'
origin=saphira-udpdist
repo=saphira
url=https://saphira.vm2.uk/
# Local source for now: the payload lives in files/ and mirrors the keeper
# repository keeper:/saphira-git-repo/saphira-udpdist.git at 03f6658,
# byte-for-byte across all 22 files. vendor=/sha256= are deliberately absent
# until a reachable public URL exists, rather than invented: a URL that cannot
# be fetched is the saphira-garden defect, and no build may depend on one.
# Business Change: new package. Layer 4 UDP distributor, DSR/LVS-DR style.
# r1: initial publication.
#   - Accepts UDP on one or more frontend address/port pairs and redirects each
#     flow at layer 2 to a backend chosen by rendezvous hashing. No address is
#     rewritten, so the backend observes the real client and replies directly:
#     ordinary UDP needs no state table, no per-flow descriptor and no
#     translation state, and the distributor is not on the return path.
#   - IPv4 and IPv6 first class. The HRW score depends on backend identity and
#     the flow alone, never on array position, so a config reorder moves
#     nothing and removing a backend moves only its own flows. Carried forward
#     from the saphira-gredist F-5 finding, which measured 32 of 56 live flows
#     moving on a pure reorder.
#   - Health probing is an in-process ICMP socket with no fork and no exec, so
#     an unresponsive peer cannot stall forwarding. Carried forward from
#     saphira-gredist F-7, which measured 5.5 s of deafness with three dead
#     backends on a 2 s tick.
#   - QUIC and HTTP/3 traverse without terminating TLS and without parsing HTTP.
#     A short-header packet carries no connection-id length, so the length comes
#     from the QUIC-LB configuration codepoint in the first connection-id
#     octet, at a fixed offset, and is never guessed. quic_mode=fallback needs
#     nothing from the backends and makes no migration claim; quic_mode=quic_lb
#     routes on routable connection ids and is the mode that earns the
#     migration-safe claim. quic_lb with an absent or invalid id configuration
#     fails validation rather than degrading quietly. Encrypted connection ids
#     are deferred so the package stays dependency-free.
#   - An established QUIC connection whose backend died is counted and dropped,
#     never re-routed to a server that does not hold its state.
#   - Non-initial fragments carry no transport header, so the first fragment's
#     choice is held in a bounded short-lived association and later fragments
#     follow it. QUIC never touches that table.
#   - Fails closed: each parse rejection has its own counter, a truncated frame
#     is never forwarded, multicast and broadcast are rejected and counted, a
#     bad or missing backend hardware address is fatal at startup rather than an
#     invisible blackhole, and a reload that cannot complete without privilege
#     is refused whole.
#   - No subpackages. A version-pinned subpackage cannot reach PASS through the
#     build daemon's INSTALL stage while that defect is unfixed, and saphira-gredist
#     is the proof; shipping without one keeps this package installable.
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
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-udpdist: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -C "$BUILDDIR/build" -j${JOBS:-$(nproc)} CC=gcc ARCH="$march" PREFIX=/usr
	# The upstream suites need layer 2 access and network namespaces, which the
	# build sandbox provides neither of. They run on the lab and via
	# tests/regress.sh, not here.
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/build/src/udpdist" "$PKGDEST/usr/bin/udpdist"
	install -D -m 0755 "$BUILDDIR/build/src/udp-send" "$PKGDEST/usr/bin/udp-send"
	install -D -m 0755 "$BUILDDIR/build/src/udp-sink" "$PKGDEST/usr/bin/udp-sink"
	install -D -m 0644 "$RECIPE_DIR/files/man/udpdist.1" \
		"$PKGDEST/usr/share/man/man1/udpdist.1"
	# Shared config root, matching the mode other Saphira daemons ship.
	install -d -m 0750 "$PKGDEST/etc/saphira"
	install -D -m 0644 "$RECIPE_DIR/files/etc/saphira/udpdist/example.conf" \
		"$PKGDEST/etc/saphira/udpdist/example.conf"
	install -D -m 0644 "$RECIPE_DIR/files/etc/saphira/udpdist/example-quic.conf" \
		"$PKGDEST/etc/saphira/udpdist/example-quic.conf"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-udpdist/LICENSE"
	# Service identity (uid/gid 152), created and converged by the packager's
	# accounts.d reconciler, the same mechanism openssh, saphira-gredist and
	# saphira-proxyto use. r2: moved off 127, which is systemd-network's.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-udpdist" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-udpdist"
	install -D -m 0755 "$RECIPE_DIR/files/tests/regress.sh" \
		"$PKGDEST/usr/share/saphira/udpdist/regress.sh"
	install -D -m 0755 "$RECIPE_DIR/files/tests/lab.sh" \
		"$PKGDEST/usr/share/saphira/udpdist/lab.sh"
}

#!/bin/sh

# tgt: Linux SCSI target framework (iSCSI target daemon for
# cinder LVM volume export; tgtadm with dual-init units, never
# enabled). Upstream feature switches for RDMA/Ceph/Gluster stay
# OFF: this package is the plain Ethernet iSCSI target cinder
# drives via tgtadm. The perl tgt-admin helper is deliberately NOT
# installed (cinder never calls it; avoids a perl runtime edge).

pkgname=tgt
pkgver=1.0.97
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux SCSI target framework (iSCSI target daemon tgtd, tgtadm)"
license="GPL-2.0-only"
origin=tgt
repo=saphira
url=https://github.com/fujita/tgt
source=https://github.com/fujita/tgt/archive/refs/tags/v1.0.97.tar.gz
sha256=459a3ee133fbd850519cde15784664934d29e5dc9680f21142247746e62d9082

# libaio-dev: the aio backstore enables only when libaio.h is
# present at build time (USE_EVENTFD); without it volumes fall
# back to synchronous I/O. gcc/binutils/make: plain C build.
depends="
	libaio
"
makedepends="
	binutils
	gcc
	make
	libaio-dev
"

recipe_build()
{
	# syntax-check the shipped init definitions
	sh -n "$RECIPE_DIR/files/tgtd.initd" || return 1
	sh -n "$RECIPE_DIR/files/tgtd.confd" || return 1
	# programs + conf only: the doc target regenerates man pages
	# via xsltproc fetching the docbook stylesheet OVER THE
	# NETWORK, which hermetic offline builds cannot do (and must
	# not). Man pages are therefore not shipped; the daemons,
	# tools and empty config are the payload.
	make -j${JOBS:-$(nproc)} \
		PREFIX=/usr \
		programs conf
}

recipe_install()
{
	make DESTDIR="$PKGDEST" \
		PREFIX=/usr \
		install-programs install-conf
	# NOTE: install-scripts is deliberately skipped: tgt-admin is
	# perl and cinder drives tgtadm directly; see the header.
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/tgt/LICENSE"
	install -D -m 0755 "$RECIPE_DIR/files/tgtd.initd" \
		"$PKGDEST/etc/init.d/tgtd"
	install -D -m 0644 "$RECIPE_DIR/files/tgtd.confd" \
		"$PKGDEST/etc/conf.d/tgtd"
	install -D -m 0644 "$RECIPE_DIR/files/tgtd.service" \
		"$PKGDEST/usr/lib/systemd/system/tgtd.service"
	for p in usr/sbin/tgtd usr/sbin/tgtadm \
		etc/tgt/targets.conf \
		etc/init.d/tgtd etc/conf.d/tgtd \
		usr/lib/systemd/system/tgtd.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: tgt payload is missing $p" >&2
			return 1
		}
	done
	# The shipped targets.conf must be the upstream EMPTY stub:
	# this package defines no targets; cinder creates them live
	# via tgtadm.
	grep -q '^include /etc/tgt/conf.d' "$PKGDEST/etc/tgt/targets.conf" || {
		echo "ERROR: tgt targets.conf is not the empty upstream stub" >&2
		return 1
	}
}

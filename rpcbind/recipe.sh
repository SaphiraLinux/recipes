#!/bin/sh
pkgname=rpcbind
pkgver=1.2.9
pkgrel=3
# r2: state dir + lock /run/* -> /var/run/* (statedir flag + source
# patch for the hardcoded lock); initd/unit wired into payload (were
# dead files); fhs.d migration. Payload change, revision bumps.
# r3: merge line (dual-init payload proofs + fhs.d declaration combined;
# merged payload differs from r2). Payload change, bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Portmap replacement for ONC RPC (required for NFSv3 and other RPC services)"
license="BSD-3-Clause"
origin=rpcbind
repo=saphira
url=https://sourceforge.net/projects/rpcbind/
# Vendored source: https://downloads.sourceforge.net/project/rpcbind/rpcbind/1.2.9/rpcbind-1.2.9.tar.bz2
rpcbind_sha256=ce5f1a87c566ef0b2897a28f50a75c1dc23fec413a46a7f4183423b6b6aa991b

depends="libtirpc"
makedepends="
	gcc
	make
	libtirpc-dev
	pkgconf
"

recipe_build()
{
	SRCBALL="$RECIPE_DIR/files/rpcbind-1.2.9.tar.bz2"
	echo "$rpcbind_sha256  $SRCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xjf "$SRCBALL"
	cd "$SRC"
	# musl has no sys/queue.h (glibc-ism). rpcbind's configure.ac
	# CLOBBERS CPPFLAGS (CPPFLAGS=$TIRPC_CFLAGS, then CPPFLAGS=), so an
	# env/include-path fix is discarded. Instead place the vendored BSD
	# queue.h (reused from the libtirpc port's queue-compat) at
	# $SRC/sys/queue.h - the automake compile lines carry -I. over the
	# source root, so <sys/queue.h> resolves without touching flags.
	# --with-systemdsystemunitdir=no: upstream's default queries
	# pkg-config for the systemd unit dir; without systemd.pc the empty
	# result is not "no", so configure enters the libsystemd check and
	# errors out. The house unit is packaged instead (files/rpcbind.service).
	mkdir -p "$SRC/sys"
	cp "$RECIPE_DIR/files/queue-compat/sys/queue.h" "$SRC/sys/queue.h"
	# Saphira split-/run layout: the lock file is hardcoded upstream
	# with no knob (only statedir is configurable).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/rpcbind-run-lock.patch"
	./configure --prefix=/usr --sbindir=/usr/sbin \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-statedir=/var/run/rpcbind \
		--with-systemdsystemunitdir=no
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Dual-init policy: both definitions ship unconditionally; neither
	# is enabled or started automatically. Upstream's own unit is
	# suppressed at configure time (--with-systemdsystemunitdir=no, see
	# recipe_build), so the house definitions are the only ones that
	# exist -- and until now they were never installed at all, which
	# left rpcbind with no way to start and left nfs-utils' four
	# After=/Wants=/Requires=rpcbind.service references dangling.
	# (Hotfix line: the house initd/unit existed in files/ but were
	# never installed - wired up here so the corrected paths take
	# effect.)
	for f in rpcbind.initd rpcbind.service; do
		[ -f "$RECIPE_DIR/files/$f" ] || {
			echo "ERROR: missing service definition $f" >&2
			return 1
		}
	done
	install -D -m 0755 "$RECIPE_DIR/files/rpcbind.initd" \
		"$PKGDEST/etc/init.d/rpcbind"
	install -D -m 0644 "$RECIPE_DIR/files/rpcbind.service" \
		"$PKGDEST/usr/lib/systemd/system/rpcbind.service"
	# Prove the payload, not just the intent: a silently absent service
	# file is the failure this package had.
	for p in etc/init.d/rpcbind usr/lib/systemd/system/rpcbind.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: rpcbind payload is missing $p" >&2
			return 1
		}
	done
	# The two definitions must agree on the command line, or one init
	# system starts a differently-configured daemon than the other.
	openrc_args=$(sed -n 's/^command_args="\(.*\)"$/\1/p' \
		"$RECIPE_DIR/files/rpcbind.initd")
	unit_args=$(sed -n 's/^ExecStart=\([^ ]*\) \(.*\)$/\2/p' \
		"$RECIPE_DIR/files/rpcbind.service")
	[ "$openrc_args" = "$unit_args" ] || {
		echo "ERROR: rpcbind init.d args '$openrc_args' != unit args '$unit_args'" >&2
		return 1
	}
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# root-run suite (no accounts.d identity); makepkg runs
	# ensure-fhs on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/rpcbind" \
		"$PKGDEST/usr/share/saphira/fhs.d/rpcbind"
}

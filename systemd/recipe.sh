#!/bin/sh

pkgname=systemd
pkgver=261.2
# r9: sysusers-native identities (reverts r8's fragment census, which
# duplicated upstream declarations and drifted): meson pins five IDs,
# files/sysusers-static-ids.patch pins oom/coredump, post-install runs
# systemd-sysusers. Legacy sidecar removed with the census (a lone
# sidecar is incoherent); stale dynamic IDs need manual userdel.
pkgrel=11
# r10: split-/run patch (PID 1, tmpfiles, D-Bus API and taint no
# longer rewrite/reject /var/run; var.conf alias line removed).
# Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="System and service manager"
license="LGPL-2.1-or-later"
origin=systemd
repo=main
url=https://systemd.io/
source=https://github.com/systemd/systemd/archive/refs/tags/v261.2.tar.gz
sha256=ed1059ff964f5df35b6056434cc17cc83f86dc913f10489948a0b19b6081c5ec

# Init-coupling invariant (dbus dragged PID-1 systemd onto OpenRC Egg
# via a runtime depends): reusable libsystemd ships as systemd-libs
# (+ systemd-dev for the headers/.pc), so library consumers never
# resolve the init package. The libs splits carry no /sbin/init, no
# units, and no accounts fragment - those stay in main only.
subpackages="
    systemd-libs
    systemd-dev
"

# udev owns the shared device-manager payload; this package is its strict
# complement and always runs alongside it.
depends="
    kmod
    libucontext
    udev
    xz
"

makedepends="
    acl-dev
    binutils
    curl-dev
    gcc
    gawk
    gperf
    kmod-dev
    libarchive-dev
    libseccomp-dev
    libucontext-dev
    saphira-kernel-headers
    lz4-dev
    make
    meson
    ninja
    openssl-dev
    pcre2-dev
    pkgconf
    python-jinja2
    python-pefile
    util-linux-dev
    xz-dev
    zstd-dev
"

recipe_build()
{
	# Feature policy: intended features are enabled explicitly with their
	# dependencies declared in makedepends, never left to environment-
	# dependent auto-detection.
	# The two static sysusers confs (oom, coredump) have no meson ID
	# knob, so their fixed IDs arrive via patch (fails closed on
	# upstream drift); the five templated ones pin below.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/sysusers-static-ids.patch"
	# Split-/run layout: upstream rewrites /var/run to /run in unit
	# parsing (Listen*, PIDFile), transient-unit properties, and
	# tmpfiles entries, taints non-symlink /var/run, and recreates
	# the alias via tmpfiles.d/var.conf. Saphira keeps both real:
	# the patch neuters the rewrites, drops the taint and the alias
	# line, touching no genuine systemd-owned /run path (fails
	# closed on upstream drift like the IDs patch).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-split-run.patch"
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Dlibc=musl \
		-Dacl=enabled \
		-Dblkid=enabled \
		-Dhibernate=true \
		-Dinitrd=true \
		-Dlibcurl=enabled \
		-Dlz4=enabled \
		-Dopenssl=enabled \
		-Dseccomp=enabled \
		-Dxz=enabled \
		-Dzstd=enabled \
		-Dtests=false \
		-Dman=disabled \
		-Dpam=disabled \
		-Dsystemd-journal-gid=131 \
		-Dsystemd-network-uid=127 \
		-Dsystemd-resolve-uid=128 \
		-Dsystemd-timesync-uid=129 \
		-Dsystemd-imds-uid=145

	# Explicit non-default states and their recorded reasons:
	#   man=disabled  queued: no python-lxml recipe; chain is
	#                 python3-dev -> python-lxml -> re-enable man and docs.
	#   pam=disabled  queued: no linux-pam recipe (flex, bison, gettext,
	#                 libtirpc all live - only the pam recipe itself is
	#                 missing); port it, then flip this flag.
	#   tests=false   payload-only build: the test suite pulls additional
	#                 introspection dependencies and ships nothing.
	# initrd/hibernate are intentional Saphira states (true): both are
	# dependency-free upstream booleans kept on deliberately.
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install

	# Strict-complement rule: remove exactly the paths owned by the shared
	# udev package so no file is ever duplicated between the two.  Keep this
	# list mirroring the udev recipe whitelist; units under
	# /usr/lib/systemd stay here even when they reference the udev daemon.
	for path in \
		bin/udevadm \
		usr/bin/udevadm \
		usr/bin/systemd-hwdb \
		lib/systemd/systemd-udevd \
		lib/udev \
		etc/udev \
		usr/include/libudev.h \
		usr/lib/libudev.a \
		usr/lib/libudev.so \
		usr/lib/libudev.so.1 \
		usr/lib/libudev.so.1.7.14 \
		usr/lib/pkgconfig/libudev.pc \
		usr/share/pkgconfig/udev.pc; do
		rm -rf -- "$PKGDEST"/$path
	done
	# Account layer is sysusers-native, not a fragment census: the
	# shipped sysusers.d confs carry Saphira-pinned fixed IDs (five
	# via meson -D above, oom/coredump via the static-ids patch), and
	# makepkg generates post-install/post-upgrade running
	# systemd-sysusers from the fragment's sysusers stanza. The
	# fragment ships main-only alongside the confs it governs.
	# r5: fragment added + xz enabled (payload changes, revision bumps).
	# r6: systemd-libs/systemd-dev splits (libsystemd out of the init
	# package; fragment stays main-only).
	# r7: ships systemd.legacy (r6 built from a pre-sidecar tree: the
	# sidecar commit landed mid-build, so receipts knew legacy while
	# the payload did not - payload presence now regression-tested).
	# r8: fragment briefly duplicated upstream IDs (drift-prone census).
	# r9: sysusers stanza replaces the census; sidecar removed with it
	# (lone sidecars are incoherent - stale dynamic IDs need manual
	# userdel, there is no automated migration without a census).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/systemd" \
		"$PKGDEST/usr/share/saphira/accounts.d/systemd"
}

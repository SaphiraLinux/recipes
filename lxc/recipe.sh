#!/bin/sh

pkgname=lxc
pkgver=7.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux container runtime (namespaces, cgroups v2, unprivileged)"
license="LGPL-2.1-or-later"
origin=lxc
repo=saphira
url=https://linuxcontainers.org/lxc/
# Official release tarball. GPG-verified: the .asc signature is Good
# over these bytes (key 602F567663E593BCBD14F338C638974D64792D67,
# Stéphane Graber) against the key GitHub's API asserts as his sole
# GPG key -- the same anchor as the release page's Verified badge.
# (Egg's gnupg ships no dirmngr -- recipe disables gnutls -- so the
# import used curl+GitHub API, not the keyserver; see memory.)
# sha256 below is enforced on every build.
source=https://linuxcontainers.org/downloads/lxc/lxc-7.0.0.tar.gz
sha256=ba0c860626efbac6683f351dd718edb062065e919716d787b89e3d547c5d9493

# DT_NEEDED set, all present in-tree: threads/libc need no entry.
# libselinux + libapparmor stay enabled per distribution policy
# (policies optional at runtime; neither LSM is required active).
# linux-pam is intentionally absent: pam-cgroup=false, so PAM is not
# even probed. dbus links systemd-libs only, never PID-1 systemd;
# systemd-dev is build-time only because dbus-1.pc Requires libsystemd
# (avahi/fwupd/openldap precedent). gcc-libs covers libgcc_s.so.1:
# upstream compiles with -fexceptions (meson RUNTIME stage will
# prove it; same finding as libselinux).
depends="
    dbus
    gcc-libs
    libapparmor
    libcap
    libseccomp
    libselinux
    openssl
"

makedepends="
    binutils
    dbus-dev
    gcc
    libapparmor-dev
    libcap-dev
    libseccomp-dev
    libselinux-dev
    make
    meson
    ninja
    openssl-dev
    pcre2-dev
    pkgconf
    python3
    saphira-linux-uapi-headers
    systemd-dev
"

# -dev takes the .a/.so unversioned link/headers/lxc.pc, -doc the
# man-free doc tree and examples, via the fixed split predicates.
# liblxc.so.1 stays in main (all consumers live under /usr).
# No -libs split (builder supports only -dev/-doc/-libs and no new
# split type is warranted): templates ship as the separate
# lxc-templates recipe from this same tarball instead.
subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	# Upstream still builds if a soft dep is missing; every
	# -D*=true below must therefore be re-proven from the meson
	# summary (a silent HAVE_*=0 would ship a neutered runtime).
	# -Dman=false: no docbook2x converter exists in-tree (libvirt
	# precedent documents the same reason). -Dtests=true compiles
	# the suite; privileged cases run post-install in isolation,
	# never in this sandbox.
	meson setup build "$SRC" --prefix=/usr \
		--sysconfdir=/etc --localstatedir=/var \
		-Dinit-script=openrc,systemd \
		-Dsystemd-unitdir=/usr/lib/systemd/system \
		-Dapparmor=true -Dselinux=true -Dseccomp=true \
		-Dcapabilities=true -Ddbus=true -Dopenssl=true \
		-Dpam-cgroup=false \
		-Dman=false -Dtests=true -Dexamples=true \
		-Dcommands=true -Dtools=true \
		-Dapi-docs=false -Dio-uring-event-loop=false \
		-Dlandlock-monitor=false \
		-Dspecfile=false -Ddistrosysconfdir=conf.d \
		-Dinstall-init-files=true -Dinstall-state-dirs=true \
		-Dthread-safety=true -Dmemfd-rexec=true
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	# Templates are the lxc-templates recipe's payload (same
	# tarball, rust-src precedent): only download+local ship there,
	# so every template leaves this payload.
	rm -rf "$PKGDEST/usr/share/lxc/templates" \
		"$PKGDEST/usr/share/lxc/config"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/lxc/COPYING"
	install -m 0644 "$SRC/LICENSE.GPL2" \
		"$PKGDEST/usr/share/licenses/lxc/LICENSE.GPL2"
	install -m 0644 "$SRC/LICENSE.LGPL2.1" \
		"$PKGDEST/usr/share/licenses/lxc/LICENSE.LGPL2.1"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/lxc" \
		"$PKGDEST/etc/logrotate.d/lxc"
	# lxc-user-nic arrives setuid-root from meson (install_mode
	# rwsr-xr-x); APK payloads cannot carry capabilities, and a
	# silently unprivileged helper would break unprivileged
	# networking, so assert the bit (shadow newuidmap precedent).
	[ -u "$PKGDEST/usr/libexec/lxc/lxc-user-nic" ] || {
		echo "ERROR: lxc-user-nic lost its setuid bit" >&2
		return 1
	}
	# Dual-init, never enabled: both families ship unconditionally.
	for p in usr/bin/lxc-ls usr/bin/lxc-info usr/bin/lxc-attach \
		usr/bin/lxc-start usr/bin/lxc-stop usr/bin/lxc-create \
		usr/bin/lxc-checkconfig \
		usr/libexec/lxc/lxc-monitord \
		usr/lib/liblxc.so.1 \
		etc/init.d/lxc-net etc/init.d/lxc-containers; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: lxc payload is missing $p" >&2
			return 1
		}
	done
	ls "$PKGDEST/usr/lib/systemd/system"/lxc*.service >/dev/null || {
		echo "ERROR: lxc payload is missing systemd units" >&2
		return 1
	}
}

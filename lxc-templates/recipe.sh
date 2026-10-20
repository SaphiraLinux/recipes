#!/bin/sh

# lxc-templates: optional LXC container-creation templates.
#
# Separate recipe from the same lxc-7.0.0 tarball (rust-src precedent):
# the builder only splits -dev/-doc/-libs, and a template set is none
# of those, so it is an independent producer. The main lxc payload
# carries no templates at all; install this only when explicitly
# requested. Only download + local ship: busybox is impossible
# (Saphira carries no busybox anywhere) and oci needs skopeo/umoci,
# which do not exist in-tree.

pkgname=lxc-templates
pkgver=7.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LXC container creation templates (download, local)"
license="LGPL-2.1-or-later"
origin=lxc-templates
repo=saphira
url=https://linuxcontainers.org/lxc/
source=https://linuxcontainers.org/downloads/lxc/lxc-7.0.0.tar.gz
sha256=ba0c860626efbac6683f351dd718edb062065e919716d787b89e3d547c5d9493

# Floor pin, not exact NVR: the resolver only resolves against live
# repository metadata, which presents the newest revision, so an exact
# pin (lxc=7.0.0-r1) is refused at plan time (proven by the first
# builder run). Template paths are baked at build time, so templates
# still rebuild alongside their lxc release via maintainer requeue.
# wget+xz+tar are the download template's hard requirements
# (its own REQUIRED-binaries loop); ca-certificates authenticates
# the HTTPS image servers.
depends="
    lxc>=7.0.0
    ca-certificates
    tar
    wget
    xz
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

recipe_build()
{
	# Duplicate of the lxc recipe's configure: the two rendered
	# templates must byte-agree with the runtime that consumes
	# them. A second few-minute C build is the price of the
	# builder's fixed split set (no controller change for this).
	meson setup build "$SRC" --prefix=/usr \
		--sysconfdir=/etc --localstatedir=/var \
		-Dinit-script=openrc,systemd \
		-Dsystemd-unitdir=/usr/lib/systemd/system \
		-Dapparmor=true -Dselinux=true -Dseccomp=true \
		-Dcapabilities=true -Ddbus=true -Dopenssl=true \
		-Dpam-cgroup=false \
		-Dman=false -Dtests=false -Dexamples=false \
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
	# Keep only the template payload: the two supported templates,
	# their common config, and our own licences. Everything else
	# belongs to lxc / lxc-dev / lxc-doc (any overlap would trip
	# the file-ownership gate).
	rm -rf "$PKGDEST/usr/bin" "$PKGDEST/usr/include" \
		"$PKGDEST/usr/lib" "$PKGDEST/usr/libexec" \
		"$PKGDEST/usr/sbin" \
		"$PKGDEST/etc" "$PKGDEST/var" \
		"$PKGDEST/usr/share/doc" "$PKGDEST/usr/share/man" \
		"$PKGDEST/usr/share/bash-completion" \
		"$PKGDEST/usr/share/lxc/hooks" \
		"$PKGDEST/usr/share/lxc/selinux" \
		"$PKGDEST/usr/share/lxc/lxc-patch.py" \
		"$PKGDEST/usr/share/lxc/lxc.functions" \
		"$PKGDEST/usr/share/lxc/templates/lxc-busybox" \
		"$PKGDEST/usr/share/lxc/templates/lxc-oci"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/lxc-templates/COPYING"
	for p in usr/share/lxc/templates/lxc-download \
		usr/share/lxc/templates/lxc-local \
		usr/share/lxc/config; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: lxc-templates payload is missing $p" >&2
			return 1
		}
	done
	for p in usr/share/lxc/templates/lxc-busybox \
		usr/share/lxc/templates/lxc-oci \
		usr/sbin/init.lxc usr/sbin/init.lxc.static \
		usr/share/lxc/lxc-patch.py usr/share/lxc/lxc.functions; do
		[ ! -e "$PKGDEST/$p" ] || {
			echo "ERROR: lxc-templates must not ship $p (owned by lxc)" >&2
			return 1
		}
	done
}

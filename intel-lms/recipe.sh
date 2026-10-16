#!/bin/sh
pkgname=intel-lms
# Upstream tag v2625.0.0.0; apk versions must start with a digit.
pkgver=2625.0.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Intel Local Manageability Service (local AMT access over MEI)'
license='Apache-2.0'
origin=intel-lms
repo=saphira
url=https://github.com/intel/lms
source=https://github.com/intel/lms/archive/refs/tags/v2625.0.0.0.tar.gz
sha256=4607374f0f66e79a7eb6400df7fdd6b5024e2e958ef518d44394f831dcbf7c44

# Daemon package, dual-init: upstream systemd unit ships (path fixed to
# /usr/lib/systemd/system below), OpenRC service added here, neither
# auto-enabled (no enablement hooks, postinst auto-start NOT adopted).
# NETWORK_NM/CN off: no NetworkManager/ConnMan in tree, so LMS uses
# netlink directly (upstream-documented reduced functionality).
# MeTee comes from the Saphira metee package (Findmetee finds
# /usr/include + libmetee; no bundled second copy, no download).
# requires_console? No: foreground daemon under supervise-daemon.
depends="ace curl glib libidn2 libnl libxml2 metee xerces-c"
makedepends="ace-dev binutils cmake curl-dev gcc glib-dev libffi-dev libidn2-dev libnl-dev libxml2-dev make metee-dev openssl-dev pcre2-dev pkgconf python3 xerces-c-dev"

recipe_build() {
	LMS_BALL="$RECIPE_DIR/files/v2625.0.0.0.tar.gz"
	echo "$sha256  $LMS_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$LMS_BALL"
	# Re-extraction refreshes the worker-prepared tree; apply patches
	# explicitly (saphira-kernel precedent).
	for patch_file in "$RECIPE_DIR"/patches/*.patch; do
		[ -f "$patch_file" ] || continue
		patch -Np1 -d "$SRC" < "$patch_file"
	done
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DNETWORK_NM=OFF \
		-DNETWORK_CN=OFF \
		-DBUILD_TESTS=OFF \
		-DBUILD_USE_CONAN=OFF
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# Upstream hardcodes /usr/lib/udev/rules.d; Saphira keeps rules in
	# /lib/udev (fuse3/libjaylink precedent).
	if [ -d "$PKGDEST/usr/lib/udev/rules.d" ]; then
		mkdir -p "$PKGDEST/lib/udev"
		mv "$PKGDEST/usr/lib/udev/rules.d" "$PKGDEST/lib/udev/rules.d"
	fi
	# Upstream unit lands wherever systemd.pc points (or /lib/systemd);
	# Saphira units live in /usr/lib/systemd/system, never elsewhere.
	mkdir -p "$PKGDEST/usr/lib/systemd/system"
	if [ -f "$PKGDEST/lib/systemd/system/lms.service" ]; then
		mv -f "$PKGDEST/lib/systemd/system/lms.service" \
			"$PKGDEST/usr/lib/systemd/system/lms.service"
	fi
	# OpenRC half of dual-init (never auto-enabled).
	install -D -m 0755 "$RECIPE_DIR/files/lms.initd" \
		"$PKGDEST/etc/init.d/lms"
	# Saphira-shaped logrotate fragment (upstream postrotate calls
	# invoke-rc.d, which does not exist here).
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/lms" \
		"$PKGDEST/etc/logrotate.d/lms"
	# State dir the daemon expects (created by Debian postinst
	# upstream; shipped here instead, no maintainer scripts).
	install -d -m 0755 "$PKGDEST/etc/lms"
}

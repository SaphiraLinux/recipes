#!/bin/sh

# audit: Linux audit framework userspace (libvirt -Daudit).
# libaudit is the client library; auditd ships with dual-init units
# (policy for daemon packages), never enabled at install. Python3
# bindings are explicitly out (--without-python3): they need swig,
# which is not packaged, and no consumer needs the bindings (libvirt
# needs libaudit only). Alpine builds them with swig; re-enable with
# swig if a bindings consumer ever appears. strndupa/basename musl
# fixes adapted from Alpine aports (same versions apply cleanly).

pkgname=audit
pkgver=4.0.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Linux audit framework userspace (libaudit, auditd)"
license="GPL-2.0-or-later AND LGPL-2.1-or-later"
origin=audit
repo=saphira
url=https://people.redhat.com/sgrubb/audit/
source=https://people.redhat.com/sgrubb/audit/audit-${pkgver}.tar.gz
sha256=d5d1b5d50ee4a2d0d17875bc6ae6bd6a7d5b34d9557ea847a39faec531faaa0a

# --with-libcap-ng=yes fails closed if libcap-ng ever vanishes
# (auto would silently drop it). --with-apparmor parses AppArmor
# audit records passively (libapparmor present, no parser needed).
makedepends="
    binutils
    gcc
    libcap-ng-dev
    libapparmor-dev
    make
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	# musl strictness fixes (Alpine aports, verified applicable to
	# 4.0.2 by real application in scratch): strndupa is glibc-only,
	# basename needs libgen.h.
	patch -Np1 -i "$RECIPE_DIR/files/0003-all-get-rid-of-strndupa.patch" || return 1
	patch -Np1 -i "$RECIPE_DIR/files/fix-basename.patch" || return 1
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--with-libcap-ng=yes \
		--without-python3 \
		--with-apparmor
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/audit/COPYING"
	install -m 0644 "$SRC/COPYING.LIB" \
		"$PKGDEST/usr/share/licenses/audit/COPYING.LIB"
	install -D -m 0755 "$RECIPE_DIR/files/auditd.initd" \
		"$PKGDEST/etc/init.d/auditd"
	install -D -m 0644 "$RECIPE_DIR/files/auditd.service" \
		"$PKGDEST/usr/lib/systemd/system/auditd.service"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# versioned .so, tools and auditd stay in main.
	for p in usr/lib/libaudit.so usr/include/libaudit.h \
		usr/sbin/auditd \
		etc/init.d/auditd \
		usr/lib/systemd/system/auditd.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: audit payload is missing $p" >&2
			return 1
		}
	done
}

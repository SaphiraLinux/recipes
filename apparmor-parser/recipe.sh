#!/bin/sh

pkgname=apparmor-parser
pkgver=4.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="AppArmor policy parser and loader (plus aa-status query tools)"
license="GPL-2.0-only"
origin=apparmor-parser
repo=saphira
url=https://apparmor.net/
# Same monorepo tarball as libapparmor (GitLab release archive, checksum
# from the v4.1.8 release notes). Only parser/ and binutils/ are built;
# libraries/ belongs to libapparmor, profiles/ ship separately once a
# policy set is decided, utils/ (perl) has no consumer.
source=https://gitlab.com/apparmor/apparmor/-/archive/v${pkgver}/apparmor-v${pkgver}.tar.gz
sha256=00f0434405f72b2a624587a92e56fd5e350af91077603b372706469f7c5e9757

depends="libapparmor"

makedepends="
    binutils
    bison
    flex
    gcc
    gettext
    libapparmor-dev
    make
    perl
    pkgconf
"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/apparmor-v4.1.8.tar.gz"
	cd "$SRC"
	echo "$sha256  $RECIPE_DIR/files/apparmor-v4.1.8.tar.gz" | sha256sum -c -
	# USE_SYSTEM=1: link the published libapparmor instead of demanding
	# an in-tree libraries/ build first (the parser Makefile refuses
	# without one or the other).
	make -C parser USE_SYSTEM=1 -j${JOBS:-$(nproc)}
	make -C binutils USE_SYSTEM=1 -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC/parser" DESTDIR="$PKGDEST" USE_SYSTEM=1 install
	make -C "$SRC/binutils" DESTDIR="$PKGDEST" USE_SYSTEM=1 install
	# Upstream installs its own apparmor.service; Saphira ships both
	# init formats itself (dual-init policy, never auto-enabled), so
	# the upstream unit must not reach the payload.
	rm -f "$PKGDEST/usr/lib/systemd/system/apparmor.service"
	[ ! -e "$PKGDEST/usr/lib/systemd/system/apparmor.service" ] || {
		echo "ERROR: upstream apparmor.service reached the payload" >&2
		return 1
	}
	# Saphira policy loader service (both inits, never enabled at
	# install: no profiles ship yet, so this is inert until a policy
	# set lands and the operator enables it).
	install -D -m 0755 "$RECIPE_DIR/files/apparmor.initd" \
		"$PKGDEST/etc/init.d/apparmor"
	install -D -m 0644 "$RECIPE_DIR/files/apparmor.service" \
		"$PKGDEST/usr/lib/systemd/system/apparmor.service"
	# The parser and the query tools are the declared capability.
	for tool in sbin/apparmor_parser usr/sbin/aa-status usr/bin/aa-enabled; do
		[ -x "$PKGDEST/$tool" ] || {
			echo "ERROR: apparmor-parser payload is missing /$tool" >&2
			return 1
		}
	done
	install -D -m 0644 "$SRC/parser/COPYING.GPL" \
		"$PKGDEST/usr/share/licenses/apparmor-parser/COPYING.GPL"
}

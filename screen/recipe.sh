#!/bin/sh

pkgname=screen
pkgver=5.0.2
pkgrel=1
# r1: initial publication. Terminal multiplexer for detachable
# sessions (operator-requested tmux companion for backgrounding
# builds). Upstream 5.0.2 defaults kept deliberately: PAM stays
# enabled (linux-pam-dev present, explicit --enable-pam, never silent
# autodetection); utmp, telnet and the global socket directory stay
# at their default-disabled (per-user sockets only, so no daemon, no
# service identity, no init files and no state packaging - a utility,
# exempt from dual-init). Upstream installs the binary setuid-root
# 4755 (multiuser attach); preserved as upstream capability, flagged
# for review, not stripped to ease the port. No invented
# /etc/screenrc (upstream ships etcscreenrc as an example only).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Terminal multiplexer (detachable sessions over one terminal)"
license="GPL-3.0-or-later"
origin=screen
repo=main
url=https://www.gnu.org/software/screen/
vendor=https://ftp.gnu.org/gnu/screen/screen-5.0.2.tar.gz
sha256=ca9a2c7e240919bc7ac12124593ae4529bb4eb5f7349d8857829b7e3f0b3b332

# Curses runtime plus PAM (explicit --enable-pam links libpam).
depends="ncurses linux-pam"

makedepends="gawk gcc linux-pam-dev make ncurses-dev"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/screen-5.0.2.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/screen-5.0.2.tar.gz" | sha256sum -c -
	cd "$SRC"
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--enable-pam
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/screen/COPYING"
	# Payload proof: the multiplexer itself must exist and execute.
	[ -x "$PKGDEST/usr/bin/screen" ] || {
		echo "ERROR: screen payload is missing usr/bin/screen" >&2
		return 1
	}
}

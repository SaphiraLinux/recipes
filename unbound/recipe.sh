#!/bin/sh
pkgname=unbound
pkgver=1.25.2
pkgrel=6
# r6: service identity 64 -> 108, convergent with the base seed
# (live systems already run 108; the 64 was never published, so no
# migration). Unblocks the seed-vs-fragment union gate. Payload
# change (fragment).
# r5: compiled pidfile default /run/unbound.pid -> /var/run/unbound.pid
# (split-/run invariant). No fhs.d fragment by rule: no directory ever
# existed (flat pidfile on tmpfs, reboot-cleared, unread post-move),
# so document-and-leave is the complete convergence. Payload change
# (compiled default), revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Validating, recursive, caching DNS resolver'
license='BSD-3-Clause'
origin=unbound
repo=saphira
url=https://nlnetlabs.nl/projects/unbound/about/
unbound_sha256=0d92275c703d5f5f8baba3dab22117dd8c29b495588a5c229768ed6581566600
depends="openssl expat"
makedepends="flex bison gawk gcc make pkgconf openssl-dev expat-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/unbound-1.25.2.tar.gz"
	cd "$SRC"
	echo "$unbound_sha256  $RECIPE_DIR/files/unbound-1.25.2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-static \
		--localstatedir=/var \
		--with-pidfile=/var/run/unbound.pid \
		--with-rootkey-file=/usr/share/dnssec-root/trusted-key.key \
		--with-username=unbound
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Service identity. --with-username=unbound above makes unbound(8)
	# drop to this user; without the fragment the identity was unowned,
	# so the configure flag proved an account the package never declared.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/unbound" \
		"$PKGDEST/usr/share/saphira/accounts.d/unbound"
	install -d -m 0755 "$PKGDEST/var/lib/unbound"
	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/unbound.initd" \
		"$PKGDEST/etc/init.d/unbound"
	install -D -m 0644 "$RECIPE_DIR/files/unbound.service" \
		"$PKGDEST/usr/lib/systemd/system/unbound.service"
	for p in etc/init.d/unbound usr/lib/systemd/system/unbound.service \
		usr/share/saphira/accounts.d/unbound; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: unbound payload is missing $p" >&2
			return 1
		}
	done
	# --with-username=unbound and the fragment must name the same user,
	# or the daemon drops to an account this package does not own.
	grep -q -- '--with-username=unbound' "$RECIPE_DIR/recipe.sh" || {
		echo "ERROR: unbound no longer configures --with-username=unbound" >&2
		return 1
	}

}

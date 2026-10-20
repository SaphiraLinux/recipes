pkgname=dhcpcd
pkgver=10.5.2
pkgrel=3
# r3: converge the state directory the client must write. The payload
# ships /var/lib/dhcpcd root-owned; the dropped-privilege daemon
# cannot store leases there, so the fragment now carries a dir stanza
# for it. Also aligns the base seed home (/var/lib/dhcpcd) with the
# fragment - installs refuse on drift.
# r2: declare the service identity. dhcpcd drops privileges to this user
# before it does anything else and refuses to run without it, so an image
# carrying no `dhcpcd` account could not run DHCP at all - and, because
# the failure surfaced as a daemonised client's silent death, it did so
# with nothing in the boot log to show for it. Upstream's install target
# creates no account, the recipe installed with a bare `make install`,
# and there is no sysusers.d fragment anywhere in the closure to replay,
# so the identity was simply unowned. This is the gap already fixed for
# frr, lldpd and mysql: the package relies on a service account the
# package never declared. dhcpcd is uid/gid 104, declared identically
# in the fragment below and in saphira-baselayout's base seed
# (accounts.tsv); the two must agree or installs refuse on drift.
# Asserted by saphira-packager/tests/recipe-rules.sh
# and by saphira-network/tests/dhcpcd-startup.sh.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='dhcpcd DHCP/DHCPv6 client with IA_PD delegation (PPP WAN support)'
license=BSD-2-Clause
origin=dhcpcd
repo=saphira
url=https://github.com/NetworkConfiguration/dhcpcd
source=https://github.com/NetworkConfiguration/dhcpcd/releases/download/v10.5.2/dhcpcd-10.5.2.tar.xz
sha256=3e476657fdb6eeb38b277da3a48d0ac0113ecce5858ebdcddff2b629faed52b4

makedepends="
	binutils
	gcc
	make
"

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --dbdir=/var/lib/dhcpcd --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Service identity. dhcpcd drops privileges to this user before it
	# does anything else and refuses to run without it. Upstream's
	# install target creates no account and there is no sysusers.d
	# fragment in the closure, so without this the identity was
	# unowned and DHCP silently could not start on any image.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/dhcpcd" \
		"$PKGDEST/usr/share/saphira/accounts.d/dhcpcd"
	install -d -m 0755 "$PKGDEST/var/lib/dhcpcd"
	for p in usr/share/saphira/accounts.d/dhcpcd; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: dhcpcd payload is missing $p" >&2
			return 1
		}
	done
}

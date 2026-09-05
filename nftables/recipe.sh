#!/bin/sh
pkgname=nftables
pkgver=1.1.6
pkgrel=9
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Netfilter nftables userspace tools'
license='GPL-2.0-only'
origin=nftables
repo=saphira
url=https://netfilter.org/projects/nftables/
nftables_sha256=372931bda8556b310636a2f9020adc710f9bab66f47efe0ce90bff800ac2530c
depends="libmnl libnftnl gmp readline jansson"
makedepends="bison flex gawk gcc make pkgconf libmnl-dev libnftnl-dev gmp-dev readline-dev jansson-dev"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/nftables-1.1.6.tar.xz"
	cd "$SRC"
	echo "$nftables_sha256  $RECIPE_DIR/files/nftables-1.1.6.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-man-doc \
		--disable-python --with-cli=readline --with-json
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	# Stage4 -> native migration regression: the old-gen package shipped
	# /etc/nftables/osf/pf.os (nft_osf passive fingerprint DB) and the
	# Saphira default /etc/nftables.conf, but the native recipe omitted
	# --sysconfdir=/etc, so r1 buried pf.os under /usr/etc and shipped no
	# conf at all; DEFAULT_INCLUDE_PATH (compiled from ${sysconfdir}) also
	# pointed at /usr/etc. sysconfdir=/etc restores the old-gen layout;
	# upstream files/osf/pf.os is byte-identical to the old-gen payload
	# (sha256 2e49e6bd...), copyright header preserved as upstream.
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Saphira default firewall/routing/NAT/IPVS-example configuration,
	# carried verbatim from the old-gen package. apk writes .apk-new if
	# a host already customises it.
	install -D -m 0644 "$RECIPE_DIR/files/nftables.conf" \
		"$PKGDEST/etc/nftables.conf"
	# Operator drop-in directory included by the default configuration.
	install -d "$PKGDEST/etc/nftables.d"
	# nftables-native classification layer (marks/sets/osf + reserved
	# NFQUEUE extension point) and its design document.
	install -d "$PKGDEST/usr/share/nftables/saphira"
	install -m 0644 "$RECIPE_DIR/files/saphira-classification.nft" \
		"$PKGDEST/usr/share/nftables/saphira/saphira-classification.nft"
	install -m 0644 "$RECIPE_DIR/files/saphira-classification-README.md" \
		"$PKGDEST/usr/share/nftables/saphira/README.md"
	# Service units for both init systems: systemd loads the ruleset at
	# boot (ExecStart nft -f), openrc uses the same via its init script.
	install -d -m 0755 "$PKGDEST/etc/init.d" "$PKGDEST/usr/lib/systemd/system"
	install -m 0755 "$RECIPE_DIR/files/nftables.initd" \
		"$PKGDEST/etc/init.d/nftables"
	install -m 0644 "$RECIPE_DIR/files/nftables.service" \
		"$PKGDEST/usr/lib/systemd/system/nftables.service"
}

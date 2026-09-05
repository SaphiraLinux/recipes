#!/bin/sh

pkgname=saphira-baselayout
pkgver=0.1
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira filesystem skeleton and platform tools (init-system neutral)"
license="MIT"
replaces="akadata-baselayout"
origin=saphira-baselayout
repo=main
url=https://saphira.vm2.uk/

depends=""

makedepends=""

# r0 of the saphira-baselayout name (continues akadata-baselayout r1):
# r0: akadata-baselayout renamed to saphira-baselayout (Genesis rebrand).
# Payload paths and env prefixes migrated (sbin/saphira-firstboot,
# /usr/libexec/saphira, /var/lib/saphira-firstboot, SAPHIRA_FIRSTBOOT_*).
# Previous restructure: every OpenRC-specific path moved out to the openrc
# package (halt/poweroff/reboot/openrc-shutdown, and the boot services
# saphira-boot-ok/net-online/network with conf.d/network).  Installing
# openrc on top of this layout reproduces the v0.1 behaviour; removing
# openrc leaves zero OpenRC traces behind.  The systemd variant needs no
# separate baselayout fork: this one is neutral.  saphira-base-abi stays
# untouched; it tracks ABI, not init systems.

recipe_build()
{
	:
}

recipe_install()
{
	install -d -m 0755 \
		"$PKGDEST/etc/conf.d" "$PKGDEST/etc/cron.daily" \
		"$PKGDEST/etc/cron.hourly" "$PKGDEST/etc/cron.monthly" \
		"$PKGDEST/etc/cron.weekly" "$PKGDEST/etc/default" \
		"$PKGDEST/etc/profile.d" "$PKGDEST/etc/skel" \
		"$PKGDEST/etc/network.d" "$PKGDEST/sbin" \
		"$PKGDEST/usr/libexec/saphira" "$PKGDEST/usr/share/saphira" \
		"$PKGDEST/var/empty" "$PKGDEST/var/lib/saphira-firstboot" \
		"$PKGDEST/var/spool/mail"
	install -m 0644 "$RECIPE_DIR/files/inittab" "$PKGDEST/etc/inittab"
	install -m 0644 "$RECIPE_DIR/files/profile" "$PKGDEST/etc/profile"
	install -m 0644 "$RECIPE_DIR/files/network.conf" \
		"$PKGDEST/etc/network.conf"
	install -m 0644 "$RECIPE_DIR/files/default-grub" \
		"$PKGDEST/etc/default/grub"
	for example in 10-eth0.conf.example 20-eth1.conf.example; do
		printf '# Example %s interface configuration.\n# INTERFACE=eth0\n# ADDRESS=192.168.0.10/24\n# GATEWAY=192.168.0.1\n' \
			"${example%%-*}" > "$PKGDEST/etc/network.d/$example"
	done
	install -m 0644 /dev/null "$PKGDEST/etc/skel/.bashrc"
	printf 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin\n' > \
		"$PKGDEST/etc/skel/.profile"
	install -m 0755 "$RECIPE_DIR/files/saphira-firstboot" \
		"$PKGDEST/sbin/saphira-firstboot"
	install -m 0755 "$RECIPE_DIR/files/saphira-network-config" \
		"$PKGDEST/sbin/saphira-network-config"
	install -m 0755 "$RECIPE_DIR/files/installkernel" \
		"$PKGDEST/sbin/installkernel"
	install -m 0755 "$RECIPE_DIR/files/nologin" "$PKGDEST/sbin/nologin"
	install -m 0755 "$RECIPE_DIR/files/libexec/apply-accounts.sh" \
		"$PKGDEST/usr/libexec/saphira/apply-accounts.sh"
	install -m 0755 "$RECIPE_DIR/files/libexec/apply-network.sh" \
		"$PKGDEST/usr/libexec/saphira/apply-network.sh"
	install -m 0644 "$RECIPE_DIR/files/accounts.tsv" \
		"$PKGDEST/usr/share/saphira/accounts.tsv"
	install -m 0755 "$RECIPE_DIR/files/libexec/configure-stage4-grub" \
		"$PKGDEST/usr/libexec/saphira/configure-stage4-grub"
}

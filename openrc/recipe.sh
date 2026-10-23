#!/bin/sh

pkgname=openrc
pkgver=0.62.1
pkgrel=8
# r8: binfmt.sh writer (2026-10-23): register/unregister writes use
# printf '%s', never echo (proven by strace: bash echo emits the trailing
# newline as a separate writev segment, the kernel runs .write once per
# segment, and the lone-newline retry fails EINVAL after the operation
# already succeeded - every fragment printed a spurious failure at every
# boot while every registration worked). Locked by tests/binfmt-writer.sh.
# r7: binfmt.sh diagnostic paths (2026-10-23): upstream lists the fragment
# dirs with trailing slashes and joins with another slash, so every
# binfmt error message prints a doubled path (/usr/lib/binfmt.d//x.conf).
# Cosmetic for file access (// opens fine) but corrosive in the one place
# you read while debugging a boot problem. No behavior change.
# r5: Saphira bootmisc never migrates /var/run or /var/lock into
# /run (upstream OpenRC does on every boot: an empty real directory
# rmdir's cleanly and is then symlinked - proven by a 0.2.1 guest
# that kept /var/run -> /run despite fhs-converge. Same patch class
# as systemd's saphira-split-run: the non-usrmerged split is policy,
# no unit or script may undo it).
# r4: depends gains findutils, procps-ng and kbd (the shipped and
# pre-enabled boot services shell out to them: bootmisc needs find,
# sysctl needs sysctl, keymaps/save-keymaps need kbd_mode/loadkeys/
# dumpkeys. Without them every OpenRC boot logs three service
# failures - proven on the 0.2.1 first boot).
# r3: own /etc/inittab (moved out of saphira-baselayout, which wrongly
# shipped this OpenRC sysvinit table on every host including systemd
# machines). Byte-identical stock content; apk ownership semantics govern
# both switch directions with no transition hooks: removing openrc
# removes the stock file, a locally modified one follows native conffile
# handling, and systemd systems never see it. Payload change.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OpenRC init system: dependency-based service management"
license="BSD-2-Clause"
origin=openrc
repo=main
url=https://github.com/OpenRC/openrc
source=https://github.com/OpenRC/openrc/archive/refs/tags/${pkgver}.tar.gz
sha256=935014044b5704b4f4e2f8b2b5faf4d1a3597f925a8a204a7a6d050060f5dcc4

depends="
    findutils
    kbd
    procps-ng
    saphira-baselayout
"

makedepends="
    gcc
    libcap-dev
    saphira-linux-uapi-headers
    meson
    ninja
    pkgconf
"

recipe_build()
{
	# Non-usrmerged boot: OpenRC's own bootmisc would migrate /var/run
	# and /var/lock into /run on every boot. Fails closed on upstream
	# drift like the systemd split-run patches.
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-no-run-migration.patch"
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-binfmt-paths.patch"
	meson setup build "$SRC" \
		--bindir=/bin --sbindir=/sbin --libdir=/lib \
		--libexecdir=/lib --buildtype=release \
		-Dos=Linux -Daudit=disabled -Dselinux=disabled -Dpam=false \
		-Dnewnet=false -Dsysvinit=true -Dbash-completions=true \
		-Dzsh-completions=false -Dpkgconfig=true -Dshell=/bin/bash
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	# Saphira platform boot services, moved out of the init-neutral
	# baselayout so removing this package removes every OpenRC trace.
	install -d -m 0755 "$PKGDEST/etc/init.d" "$PKGDEST/etc/conf.d"
	# The sysvinit table belongs to OpenRC (PID 1 selection), not the
	# init-neutral baselayout: installing openrc provides it, removing
	# openrc removes the stock file via apk ownership. Byte-identical
	# to the former baselayout copy; never modified, never symlinked.
	install -m 0644 "$RECIPE_DIR/files/inittab" "$PKGDEST/etc/inittab"
	install -m 0755 "$RECIPE_DIR/files/openrc-boot/saphira-boot-ok" \
		"$PKGDEST/etc/init.d/saphira-boot-ok"
	install -m 0755 "$RECIPE_DIR/files/openrc-boot/net-online" \
		"$PKGDEST/etc/init.d/net-online"
	install -m 0755 "$RECIPE_DIR/files/openrc-boot/network.initd" \
		"$PKGDEST/etc/init.d/network"
	install -m 0644 "$RECIPE_DIR/files/openrc-boot/confd-network" \
		"$PKGDEST/etc/conf.d/network"
}

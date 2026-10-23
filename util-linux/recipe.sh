#!/bin/sh
pkgname=util-linux
pkgver=2.41.1
# r8: rebuild against musl r5 headers so direct-file utmp readers
# (notably last) resolve the real database paths instead of
# musl upstream's /dev/null placeholders. No source change;
# the embedded _PATH_WTMP moves from /dev/null/wtmp to
# /var/log/wtmp, which the Stage4 writer maintains.
pkgrel=9
# r9: shell-continuation repair + capability restoration (2026-10-23):
# the meson flag list is whole again (stub-proven; the r8 truncation is
# locked by saphira-packager/tests/shell-continuation.sh), write enabled
# (upstream 2755 root:tty pair with wall, asserted below), runuser
# restored (linux-pam-dev + pam.d service files; selinux-role support
# stays out while selinux is disabled), audit/smack explicit. pg/ul stay
# absent pending the ncurses ticlib ABI slice (documented, not dropped).
# Payload change.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Miscellaneous Linux utilities (mount, lsblk, blkid, fdisk, dmesg)'
license='GPL-2.0-or-later LGPL-2.1-or-later BSD-3-Clause'
origin=util-linux
repo=saphira
url=https://github.com/util-linux/util-linux
util_linux_sha256=be9ad9a276f4305ab7dd2f5225c8be1ff54352f565ff4dede9628c1aaa7dec57
depends="ncurses readline zlib"
makedepends="bison flex gcc gettext libxcrypt-dev readline-dev saphira-linux-uapi-headers meson ninja pkgconf python3 zlib-dev ncurses-dev linux-pam-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/util-linux-2.41.1.tar.xz"
	cd "$SRC"
	echo "$util_linux_sha256  $RECIPE_DIR/files/util-linux-2.41.1.tar.xz" | sha256sum -c -
	# readline is NOT optional here, and disabling it silently deletes
	# two tools the pkgdesc advertises. In util-linux 2.41.1
	# lib_readline = dependency('readline', required:
	# get_option('readline')), so `-Dreadline=disabled` makes that a
	# meson DISABLER, and meson silently skips every target that
	# depends on a disabler. The only four such targets are fdisk,
	# fdisk.static, sfdisk and sfdisk.static -- so fdisk and sfdisk
	# were NOT BUILT AT ALL, and the `[ -e ]' guards in
	# recipe_install hid the absence. saphira-image hard-requires
	# sfdisk, so image creation could not have worked.
	# (Comment lives here, never inside the invocation below: a comment
	# line inside a backslash continuation truncates the flag list --
	# the shell joins the flag line with the comment and every later
	# flag becomes a command. That exact shape shipped r8 with only
	# the first nine flags, so libmount/python never saw its disable
	# and the build died on the missing python3-dev. Proven by stub
	# reproduction and the retained meson-log Build Options line.)
	# tinfo stays disabled in this slice (pg/ul absent by consequence,
	# documented as pending restoration, not unsupported): enabling it
	# needs an ncurses ticlib split first, which is its own ABI slice.
	# runuser is restored via linux-pam-dev (su-common.c needs PAM
	# headers unconditionally) plus the pam.d service files below;
	# have_pty is proven at build time. runuser ships without
	# --selinux-role support while selinux stays disabled (recorded).
	# write is enabled with wall/mesg (upstream setgid-tty pair, pinned
	# below); audit/smack are explicit, matching effective state.
	meson setup _build --prefix=/usr \
		--libdir=/usr/lib \
		-Dsystemd=disabled \
		-Dsysvinit=disabled \
		-Dtinfo=disabled \
		-Deconf=disabled \
		-Dselinux=disabled \
		-Dslang=disabled \
		-Dlibutil=disabled \
		-Dlibuser=disabled \
		-Dlibutempter=disabled \
		-Dreadline=enabled \
		-Dbuild-python=disabled \
		-Dbuild-plymouth-support=disabled \
		-Dbuild-agetty=enabled \
		-Dbuild-chfn-chsh=disabled \
		-Dbuild-newgrp=disabled \
		-Dbuild-login=disabled \
		-Dbuild-nologin=disabled \
		-Dbuild-su=disabled \
		-Dbuild-sulogin=enabled \
		-Dbuild-wall=enabled \
		-Dbuild-write=enabled \
		-Dbuild-cal=enabled \
		-Dbuild-kill=enabled \
		-Dbuild-mesg=enabled \
		-Dbuild-more=enabled \
		-Dbuild-setarch=enabled \
		-Dbuild-switch_root=enabled \
		-Dbuild-vipw=disabled \
		-Dbuild-pam-lastlog2=disabled \
		-Dbuild-liblastlog2=disabled \
		-Daudit=disabled \
		-Dsmack=disabled \
		-Dtty-setgid=true
	meson compile -C _build
}
recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C "$SRC/_build"
	rm -f "$PKGDEST/sbin/nologin"
	# PAM service entries for runuser (mirrors the openssh/shadow
	# pattern: each service owns its /etc/pam.d entry). Without these,
	# runuser cannot authenticate even for root.
	install -D -m 0644 "$RECIPE_DIR/files/pam.d/runuser" \
		"$PKGDEST/etc/pam.d/runuser"
	install -D -m 0644 "$RECIPE_DIR/files/pam.d/runuser-l" \
		"$PKGDEST/etc/pam.d/runuser-l"
	# Maintainer hook (post-install + post-upgrade): converge wall/write
	# to 2755 root:tty at install time, where tty exists. The declaration
	# is stripped from the payload, so the generated script is the only
	# shipped copy and `apk adbdump` is the audit trail.
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/util-linux"
	install -m 0755 "$RECIPE_DIR/files/hooks-wall-write" \
		"$PKGDEST/usr/share/saphira/hooks.d/util-linux/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-wall-write" \
		"$PKGDEST/usr/share/saphira/hooks.d/util-linux/post-upgrade"
	# Saphira is deliberately NOT usrmerged: system binaries live in /bin
	# and /sbin, where systemd units and OpenRC init scripts expect them
	# (r2 shipped them under /usr and broke both inits - see the r0/r2/r3
	# boot matrix). Restore the proven r0 layout.
	bin_tools="dmesg findmnt lsblk lsfd more mount mountpoint pipesz umount wdctl"
	sbin_tools="agetty blkdiscard blkid blkpr blkzone blockdev cfdisk chcpu ctrlaltdel fdisk findfs fsck fsck.cramfs fsck.minix fsfreeze fstrim hwclock losetup mkfs mkfs.bfs mkfs.cramfs mkfs.minix mkswap pivot_root runuser sfdisk sulogin swaplabel swapoff swapon switch_root wipefs zramctl"
	install -d "$PKGDEST/bin" "$PKGDEST/sbin"
	for tool in $bin_tools; do
		[ -e "$PKGDEST/usr/bin/$tool" ] && mv "$PKGDEST/usr/bin/$tool" "$PKGDEST/bin/$tool"
	done
	for tool in $sbin_tools; do
		[ -e "$PKGDEST/usr/sbin/$tool" ] && mv "$PKGDEST/usr/sbin/$tool" "$PKGDEST/sbin/$tool"
	done
	# The fdisk family is a declared capability, not a hope. These four
	# were silently absent because -Dreadline=disabled turned lib_readline
	# into a meson disabler and meson skips disabler-dependent targets
	# without a word. Refuse the build rather than publish a package whose
	# pkgdesc lies, because saphira-image partitions disks with sfdisk and
	# an image without it is unbuildable.
	for tool in fdisk sfdisk; do
		[ -x "$PKGDEST/sbin/$tool" ] || {
			echo "ERROR: util-linux payload is missing /sbin/$tool" >&2
			echo "       (fdisk/sfdisk depend on lib_readline; check -Dreadline)" >&2
			return 1
		}
	done
	# runuser and write are restored capabilities in r9: same treatment.
	# runuser must survive PAM/pty detection (a quiet .require() skip
	# would otherwise drop it exactly like the fdisk incident).
	for tool in runuser; do
		[ -x "$PKGDEST/sbin/$tool" ] || {
			echo "ERROR: util-linux payload is missing /sbin/$tool" >&2
			echo "       (runuser needs linux-pam-dev + have_pty)" >&2
			return 1
		}
	done
	[ -x "$PKGDEST/usr/bin/write" ] || {
		echo "ERROR: util-linux payload is missing /usr/bin/write" >&2
		return 1
	}
	# Upstream setgid-tty pair (wall/write carry the setuid bit via
	# -Dtty-setgid; tty is GID 5 in baselayout accounts). The clean
	# build root carries no tty group, so the group cannot be staged
	# (numeric chown to an unmapped GID fails in the rootless
	# namespace): the build asserts the staged 2755 mode here, and the
	# hooks-wall-write maintainer hook converges 2755 root:tty at
	# install/upgrade time, where the base seed guarantees tty.
	# mount/umount stay plain 0755 per the r0 precedent (setuid mount is
	# not wanted); wall/write need group tty to reach other users'
	# terminals, which is their entire function.
	for pair in "usr/bin/wall" "usr/bin/write"; do
		[ "$(stat -c '%a' "$PKGDEST/$pair")" = "2755" ] || {
			echo "ERROR: $pair must carry the setuid bit (2755), found $(stat -c '%a %u %g' "$PKGDEST/$pair")" >&2
			return 1
		}
	done
	# mount/umount stay plain 0755 per the r0 precedent (setuid mount is
	# not wanted and the system boots without it).
	chmod 0755 "$PKGDEST/bin/mount" "$PKGDEST/bin/umount"
	# FHS non-usrmerged: /bin|/sbin consumers (mount, fsck, blkid,
	# fdisk family) need the runtime SONAME chain in /lib; dev
	# linker names stay in /usr/lib pointing back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libblkid.so.1"* "$PKGDEST/usr/lib/libmount.so.1"* \
		"$PKGDEST/usr/lib/libsmartcols.so.1"* "$PKGDEST/usr/lib/libfdisk.so.1"* \
		"$PKGDEST/usr/lib/libuuid.so.1"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	for dev in libblkid.so libmount.so libsmartcols.so libfdisk.so libuuid.so; do
		link="$PKGDEST/usr/lib/$dev"
		[ -L "$link" ] || continue
		target=$(readlink "$link")
		case $target in */*) continue;; esac
		[ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link"
	done
}

#!/bin/sh
pkgname=shadow
pkgver=4.17.3
pkgrel=10
# r10: merge line (explicit --localstatedir=/var adopted from the
# hotfix configure-hygiene sweep; hatched publishes r9 built without
# it and localstatedir-derived compiled paths may shift payload
# bytes, so the merged recipe takes the next revision).
# Payload change, bumps.
# r9: opt into libxcrypt explicitly. The generic -lcrypt name is musl'"'"'s and
# resolves crypt() out of libc, so AC_CHECK_LIB(crypt,...) succeeds while
# quietly selecting musl. shadow calls crypt_gensalt(), which musl does not
# provide, so this is a build requirement, not a preference. The patch
# prefers -lxcrypt and the recipe puts libxcrypt'"'"'s include directory first.
# r8: rebuilt against libxcrypt-4.4.38-r5, which completes the musl crypt
# policy with a dummy libcrypt link name instead of deleting it. No recipe
# change: shadow still asks configure for -lcrypt, which now links and
# resolves crypt() from musl's libc. Bumped because the payload changes.
# r7: subordinate-ID helpers use upstream's DEFAULT privilege model (setuid
# root), not --with-fcaps. r6 was published with --with-fcaps and shipped
# newuidmap/newgidmap at mode 0755 with NO privilege: the apk payload cannot
# carry security.capability, so the caps were dropped silently and the
# helpers could not work. makepkg now refuses any capability-bearing
# payload, and the setuid bits are preserved. r6 is superseded and must not
# remain as the current revision.
# r6: subordinate IDs enabled (--enable-subordinate-ids). Required for
# unprivileged container UID/GID mapping: newuidmap/newgidmap plus
# /etc/subuid and /etc/subgid are how an unprivileged user is permitted to
# map a range of subordinate IDs. The previous --without-subordinate-ids
# did not merely disable useradd's range allocation -- src/Makefile.am
# gates upstream's own setcap of newuidmap/newgidmap on ENABLE_SUBIDS, so
# the helpers shipped with no privilege at all and could not work. Payload
# change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Password and account management tools with PAM (login, su, passwd, chage)'
license='BSD-3-Clause GPL-2.0-or-later'
origin=shadow
repo=saphira
url=https://github.com/shadow-maint/shadow
shadow_sha256=2a029091d2c2f116f51b3a817ec16e7da22310a6c8116394457483c668c84b36
# linux-pam: linked at build (headers in linux-pam-dev since the r4
# -dev split) and needed at runtime by login/su/passwd.
depends="libxcrypt acl attr libbsd libmd linux-pam saphira-pambase"
# libcap is a makedepends-only input: it provides setcap/getcap, which
# --with-fcaps needs at install time to set and then VERIFY the helpers'
# privileges. shadow does not link libcap (configure never sets LIBCAP),
# so it is deliberately not a runtime dependency.
makedepends="autoconf automake libcap libtool gettext libxcrypt-dev acl-dev attr-dev libbsd-dev libmd-dev linux-pam linux-pam-dev gcc make pkgconf"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/shadow-4.17.3.tar.gz"
	cd "$SRC"
	echo "$shadow_sha256  $RECIPE_DIR/files/shadow-4.17.3.tar.gz" | sha256sum -c -
	# official release tarball ships pre-generated configure
	# --enable-subordinate-ids, and deliberately NOT --with-fcaps.
	#
	# --with-fcaps is shadow's least-privilege mode: setcap cap_setuid+ep on
	# newuidmap and cap_setgid+ep on newgidmap instead of setuid. It is not
	# used here because Saphira's apk payload cannot store file
	# capabilities: they are dropped silently, so the helpers shipped at
	# mode 0755 with no privilege at all and could never map a UID for
	# anyone. makepkg now refuses any payload carrying
	# security.capability rather than letting that happen quietly, and the
	# fix is to use the mechanism that does survive.
	#
	# Upstream's DEFAULT is the setuid mode, and that is what is used: the
	# helpers are in suidubins, so they are installed setuid root (04755) and
	# those mode bits are preserved through packaging. So this is upstream
	# semantics, not a Saphira-specific privilege workaround.
	# The generic crypt namespace is musl's, and shadow must opt into
	# libxcrypt explicitly rather than reach it by accident through -lcrypt.
	# The patch prefers -lxcrypt; CPPFLAGS puts libxcrypt's include
	# directory ahead of the generic one so <crypt.h> is the extended API
	# that declares crypt_gensalt(), which lib/salt.c calls and musl does
	# not provide. Without both halves shadow silently builds against musl's
	# crypt, or fails to build at all.
	patch -Np1 -i "$RECIPE_DIR/files/0001-saphira-prefer-libxcrypt.patch"
	./configure --prefix=/usr --sysconfdir=/etc --disable-static \
		--localstatedir=/var \
		CPPFLAGS="-I/usr/include/libxcrypt ${CPPFLAGS-}" \
		--with-libpam --without-selinux \
		--without-audit --enable-subordinate-ids \
		--without-btrfs --disable-nls \
		--with-group-name-max-length=32
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# saphira-baselayout owns
	# /sbin/nologin; yield it until the baselayout migration replaces
	# it, otherwise every shadow upgrade collides with apk fix.
	rm -f "$PKGDEST/sbin/nologin"
	# Saphira setuid policy: explicit modes for the privileged tools.
	# makepkg preserves these bits through the rootless chown (r18).
	for tool in passwd chage chsh gpasswd newgrp; do
		[ -f "$PKGDEST/usr/bin/$tool" ] && chmod 4755 "$PKGDEST/usr/bin/$tool"
	done
	# Subordinate-ID databases. These are MANAGED FILES, not templates
	# with content: useradd/newuserid append the ranges they allocate, so
	# the package ships them present-but-empty and world-readable but not
	# writable. Hard-coding a user or a range here would be both a policy
	# decision taken in the wrong place and a silent override of whatever
	# login.defs says, so the allocation stays entirely with
	# account-management tooling. An existing user with no entry here stays
	# valid: absence of a range only means it cannot map subordinate IDs.
	install -D -m 0644 /dev/null "$PKGDEST/etc/subuid"
	install -D -m 0644 /dev/null "$PKGDEST/etc/subgid"
	# The allocation policy itself is NOT invented here. shadow's own
	# etc/login.defs ships it, and it is installed with the package:
	#   SUB_UID_MIN 100000  SUB_UID_MAX 600100000  SUB_UID_COUNT 65536
	#   SUB_GID_MIN 100000  SUB_GID_MAX 600100000  SUB_GID_COUNT 65536
	# COUNT 65536 is the 64K range a user namespace needs, and the MIN/MAX
	# window keeps allocated ranges well clear of the system UID space. The
	# install asserts the policy actually arrived, because a recipe change
	# that dropped the login.defs block would leave useradd silently unable
	# to allocate anything -- with no error anywhere.
	login_defs=$PKGDEST/etc/login.defs
	[ -f "$login_defs" ] ||
		{ echo "ERROR: shadow did not install /etc/login.defs" >&2; return 1; }
	for knob in SUB_UID_MIN SUB_UID_MAX SUB_UID_COUNT \
		SUB_GID_MIN SUB_GID_MAX SUB_GID_COUNT; do
		grep -qE "^[[:space:]]*$knob[[:space:]]+[0-9]+" "$login_defs" ||
			{
				echo "ERROR: $knob missing from login.defs; subordinate-ID" >&2
				echo "       allocation has no policy and would silently do nothing." >&2
				return 1
			}
	done
	# The helpers must actually be privileged, and that is verified rather
	# than assumed. Upstream's default model is that newuidmap/newgidmap are
	# in suidubins, i.e. installed setuid root. Assert setuid SPECIFICALLY
	# here, not "privileged somehow": a file capability would satisfy a
	# looser check while shipping with no privilege at all, which is exactly
	# what --with-fcaps did before makepkg learned to refuse capabilities.
	for pair in newuidmap:cap_setuid newgidmap:cap_setgid; do
		tool=${pair%%:*}
		path=$PKGDEST/usr/bin/$tool
		[ -f "$path" ] ||
			{ echo "ERROR: $tool was not built" >&2; return 1; }
		[ "$(stat -c '%u:%g' "$path")" = "0:0" ] ||
			{
				echo "ERROR: $tool is not root-owned" >&2
				return 1
			}
		mode=$(stat -c '%a' "$path")
		case $mode in
		4*) : ;;
		*)
			echo "ERROR: $tool is mode $mode, not setuid." >&2
			echo "       Without setuid (or a capability the payload cannot" >&2
			echo "       carry) it cannot map subordinate IDs for anyone." >&2
			return 1
			;;
		esac
		# A capability here would mean the recipe is back on a mechanism
		# the payload drops, so refuse it by name too.
		if getcap "$path" 2>/dev/null | grep -q .; then
			echo "ERROR: $tool carries a file capability: $(getcap "$path")" >&2
			echo "       the apk payload would drop it and ship the helper" >&2
			echo "       unprivileged. Use the setuid bit." >&2
			return 1
		fi
	done
	# PAM service entries: linux-pam ships no service files and
	# saphira-pambase ships only the shared stacks; each service
	# owns its leaf file (openssh precedent). Without these,
	# PAM-linked login/su would deny all authentications.
	for svc in login su su-l passwd chfn chsh chpasswd newusers; do
		install -D -m 0644 "$RECIPE_DIR/files/pam.d/$svc" \
			"$PKGDEST/etc/pam.d/$svc"
	done
}

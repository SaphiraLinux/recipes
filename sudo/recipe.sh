#!/bin/sh
pkgname=sudo
pkgver=1.9.17_p2
pkgrel=8
# r8: owned /etc/sudoers (existing grants verbatim + canonical
# secure_path): without it sudo inherits whatever PATH the caller
# had, which varies silently across console/ssh/cron/service
# contexts. Operator modifications park as .apk-new as usual.
# r7: merge line (explicit --sysconfdir=/etc + --localstatedir=/var
# adopted from the hotfix configure-hygiene sweep; hatched publishes
# r6 built without them and localstatedir-derived compiled paths may
# shift payload bytes, so the merged recipe takes the next revision).
# Payload change, bumps.
# r6: PAM enabled (linux-pam 1.7.2 + saphira-pambase now in tree):
# --with-pam; ships the sudo leaf file. Payload change, bumps.
# r5: sudoers.d ships 0750 (homer recon: Arch sudo carries 0750;
# upstream make install leaves 0755, which is needlessly broad for
# a privilege-config directory). Payload change, revision bumps.
# (r5 published from another branch; adopted here so this lineage
# never regresses it.)
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Give limited users limited root privileges'
license='ISC'
origin=sudo
repo=saphira
url=https://www.sudo.ws/
sudo_sha256=4a38a1ab3adb1199257edc2a7c4a2bd714665eb605b04368843b06dada2cfcfb
# linux-pam: linked at build (headers in the single-output package,
# no -dev split) and needed at runtime.
depends="zlib linux-pam saphira-pambase"
makedepends="zlib-dev linux-pam gcc make"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/sudo-1.9.17_p2.tar.gz"
	cd "$SRC"
	echo "$sudo_sha256  $RECIPE_DIR/files/sudo-1.9.17_p2.tar.gz" | sha256sum -c -
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-pam --without-sssd --without-ldap \
		--without-selinux --without-sendmail \
		--disable-nls --disable-static \
		--with-logfac=authpriv
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Owned sudoers (Saphira PATH policy): upstream installs a minimal
	# file with just the grants; the canonical secure_path belongs to
	# the same owned content so sudo sessions agree with login shells
	# regardless of the caller's environment. Existing grants preserved
	# verbatim; upgrades park operator modifications as .apk-new.
	install -m 0440 "$RECIPE_DIR/files/sudoers" \
		"$PKGDEST/etc/sudoers"
	# Least-privilege payload: sudoers.d holds privilege config,
	# so it ships 0750 even though upstream installs 0755.
	install -d -m 0750 "$PKGDEST/etc/sudoers.d"
	# PAM service entry (saphira-pambase carries the shared stacks).
	install -D -m 0644 "$RECIPE_DIR/files/pam.d/sudo" \
		"$PKGDEST/etc/pam.d/sudo"
	# Saphira setuid policy (hatchling sudo incident, memory note):
	# explicit 4755 so same-version reinstalls can never strip the bit.
	chmod 4755 "$PKGDEST/usr/bin/sudo" "$PKGDEST/usr/bin/sudoedit"
	ls -l "$PKGDEST/usr/bin/sudo" >&2
	stat -c "staged-mode=%a" "$PKGDEST/usr/bin/sudo" >&2
}

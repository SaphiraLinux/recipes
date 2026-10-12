pkgname=saphira-base-accounts
pkgver=0.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira base account database skeleton (clean passwd, group, shadow)'
license='BUSL-1.1'
origin=saphira-base-accounts
repo=saphira
url=https://saphira.vm2.uk/

# No source: local package, nothing to fetch. No payload files either:
# the account files are created by the install hooks only where absent,
# so installing this package can never clobber a live account database.
# (The other side of that guarantee: apk fix will not restore them.)
depends=""
makedepends=""

recipe_build() {
	:
}

recipe_install() {
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-accounts" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-accounts" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
}

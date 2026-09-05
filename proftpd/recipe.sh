pkgname=proftpd
pkgver=1.3.9
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='High-performance, scalable FTP server (with TLS via mod_tls)'
license='GPL-2.0-or-later'
origin=proftpd
repo=saphira
url=https://proftpd.org/
source=https://github.com/proftpd/proftpd/archive/refs/tags/v${pkgver}.tar.gz
sha256=4a5f13b666226813b4da0ade34535d325e204ab16cf8008c7353b1b5a972f74b

depends="openssl libcap"
makedepends="gcc make libcap-dev openssl-dev pkgconf saphira-kernel-headers=7.1.5"
subpackages="$pkgname-doc"

recipe_build() {
	./configure --prefix=/usr --sysconfdir=/etc \
		--enable-openssl \
		--with-modules=mod_tls \
		--disable-strip
	make -j${JOBS:-$(nproc)} INSTALL_GROUP=root
}

recipe_install() {
	# proftpd's install hardcodes -o/-g ownership (including contrib's
	# raw $(INSTALL) uses), but the clean root has no /etc/passwd, so
	# install(1) cannot resolve even "root". Seed a minimal entry in
	# the disposable workspace root (never packaged - only $PKGDEST
	# becomes the APK).
	[ -f /etc/passwd ] || { mkdir -p /etc; \
		echo 'root:x:0:0:root:/:/bin/sh' > /etc/passwd; }
	[ -f /etc/group ] || echo 'root:x:0:' > /etc/group
	make DESTDIR="$PKGDEST" INSTALL_USER=root INSTALL_GROUP=root install

	# Saphira default configuration (adapted from upstream basic.conf:
	# nobody:nobody daemon account, anonymous ftp:ftp on /srv/ftp).  apk
	# treats /etc paths as protected on upgrade, so an operator-modified
	# proftpd.conf is preserved and the new default lands as .apk-new.
	install -Dm0644 "$RECIPE_DIR/files/proftpd.conf" \
		"$PKGDEST/etc/proftpd.conf"

	# Anonymous FTP document root: read-only under the default config,
	# root-owned 0755 (not world-writable); install -d is idempotent so
	# existing operator content is never overwritten during upgrades.
	install -d -m 0755 "$PKGDEST/srv/ftp"

	# Dual-init policy: both formats ship unconditionally, neither is
	# enabled automatically, neither wraps the other.
	install -Dm0755 "$RECIPE_DIR/files/proftpd.initd" \
		"$PKGDEST/etc/init.d/proftpd"
	install -Dm0644 "$RECIPE_DIR/files/proftpd.service" \
		"$PKGDEST/usr/lib/systemd/system/proftpd.service"
}

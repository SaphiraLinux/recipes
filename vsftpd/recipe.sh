pkgname=vsftpd
pkgver=3.0.5
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Very Secure FTP daemon - small, fast, secure FTP server'
license='GPL-2.0-or-later'
origin=vsftpd
repo=saphira
url=https://security.appspot.com/vsftpd.html
# Upstream release tarball, bytes pinned (hash matches the upstream
# published checksum).
source=https://security.appspot.com/downloads/vsftpd-${pkgver}.tar.gz
sha256=26b602ae454b0ba6d99ef44a09b6b9e0dfa7f67228106736df1f278c70bc91d3

depends="openssl libxcrypt libcap"
makedepends="gcc make openssl-dev libxcrypt-dev libcap-dev saphira-kernel-headers=7.1.5"

recipe_build() {
	# Vanilla build: vsftpd's Makefile locates openssl itself; libcap is
	# optional and not enabled. Upstream CFLAGS carry -Werror which
	# trips on musl's harmless <sys/fcntl.h> redirect warning - drop it
	# and provide the musl WTMPX_FILE define (glibc-only macro).
	patch -N -s -p1 -i "$RECIPE_DIR/files/saphira-musl.patch"
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	install -D -m 0755 vsftpd "$PKGDEST/usr/sbin/vsftpd"
	install -D -m 0644 vsftpd.conf "$PKGDEST/etc/vsftpd/vsftpd.conf" \
		|| install -D -m 0644 "$SRC/vsftpd.conf" "$PKGDEST/etc/vsftpd/vsftpd.conf"
	install -D -m 0644 vsftpd.8 "$PKGDEST/usr/share/man/man8/vsftpd.8"
	install -D -m 0644 vsftpd.conf.5 "$PKGDEST/usr/share/man/man5/vsftpd.conf.5"
	install -D -m 0644 EXAMPLE/INTERNET_SITE/vsftpd.xinetd \
		"$PKGDEST/usr/share/doc/vsftpd/examples/vsftpd.xinetd"
	# Dual-init policy: both formats ship unconditionally, neither is
	# enabled automatically, neither wraps the other.
	install -D -m 0755 "$RECIPE_DIR/files/vsftpd.initd" \
		"$PKGDEST/etc/init.d/vsftpd"
	install -D -m 0644 "$RECIPE_DIR/files/vsftpd.service" \
		"$PKGDEST/usr/lib/systemd/system/vsftpd.service"
}

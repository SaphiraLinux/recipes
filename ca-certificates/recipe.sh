#!/bin/sh

pkgname=ca-certificates
pkgver=20260831
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='CA certificate bundle + Saphira native update-ca-certificates'
license='MPL-2.0'
origin=ca-certificates
repo=saphira
url=https://curl.se/docs/caextract.html
# cacert.pem snapshot: https://curl.se/ca/cacert.pem (Mozilla set)
cacert_sha256=f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9

depends=""
makedepends="gawk gcc make"

recipe_build()
{
	CCB="$RECIPE_DIR/files/update-ca-certificates.c"
	gcc ${CFLAGS:--Os} -s -o update-ca-certificates "$CCB"
	# Split the Mozilla bundle into individual certificates; conf lists
	# each as mozilla/NNN.crt (the standard ca-certificates scheme).
	mkdir -p certs/mozilla
	awk '/BEGIN CERT/{n++; f=sprintf("certs/mozilla/%04d.crt", n)} n{print > f}' \
		"$RECIPE_DIR/files/cacert.pem"
	[ "$(ls certs/mozilla | wc -l)" -gt 100 ] || { echo "cert split failed" >&2; return 1; }
	: > certlist
	for c in certs/mozilla/*.crt; do
		echo "mozilla/$(basename "$c")" >> certlist
	done
}

recipe_install()
{
	install -D -m 0755 update-ca-certificates "$PKGDEST/usr/sbin/update-ca-certificates"
	install -d "$PKGDEST/usr/share/ca-certificates/mozilla" \
		"$PKGDEST/etc/ssl/certs" "$PKGDEST/etc/ca-certificates/update.d" \
		"$PKGDEST/usr/local/share/ca-certificates" "$PKGDEST/etc/apk"
	cp -a certs/mozilla/. "$PKGDEST/usr/share/ca-certificates/mozilla/"
	install -m 0644 certlist "$PKGDEST/etc/ca-certificates.conf"
	# Normal OpenSSL trust path (OPENSSLDIR=/etc/ssl: the default
	# verification reads /etc/ssl/cert.pem) plus apk-tools TLS.
	ln -sf certs/ca-certificates.crt "$PKGDEST/etc/ssl/cert.pem"
	ln -sf /etc/ssl/certs/ca-certificates.crt "$PKGDEST/etc/apk/ca.pem"
}

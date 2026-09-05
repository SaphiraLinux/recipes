#!/bin/sh

pkgname=php85
pkgver=8.5.9
pkgrel=7
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PHP 8.5 language runtime: CLI, FPM, opcache and shared extensions"
license="PHP-3.01"
origin=php85
repo=main
url=https://www.php.net/
source=https://www.php.net/distributions/php-8.5.9.tar.xz
sha256=0db7855f25bcd0ab1d592cdb35e284d6f6a5d2ae0f6f621122e364cc39b708f4

depends="
    curl
    libxml2
    libzip
    oniguruma
    openssl
    sqlite
    zlib
"

makedepends="
    binutils
    curl-dev
    gcc
    gawk
    libxml2-dev
    libzip-dev
    musl-fts-dev
    make
    libargon2-dev
    oniguruma-dev
    openssl-dev
    pkgconf
    sqlite-dev
    zstd-dev
    zlib-dev
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Dual-format service package; ships a real /etc/php85/php-fpm.conf
	# (upstream only leaves php-fpm.conf.default) and enables the bundled
	# opcache as a shared extension.
	#
	# r3: curl, zip and mbstring extensions enabled - their build-time
# libraries (curl, libzip, oniguruma) are published now.
	# libraries (libcurl, libzip, oniguruma) are available in the repo.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--program-suffix=85 \
		--with-config-file-path=/etc/php85 \
		--with-config-file-scan-dir=/etc/php85/conf.d \
		--enable-cli --enable-fpm --enable-opcache=shared \
		--with-mysqli=shared,mysqlnd \
		--with-pdo-mysql=shared,mysqlnd --with-pdo-sqlite=shared \
		--with-curl=shared --with-zip=shared --enable-mbstring=shared \
		--enable-dom=shared --enable-simplexml=shared \
		--enable-xml=shared --enable-xmlreader=shared --enable-xmlwriter=shared \
		--with-password-argon2 \
		--with-openssl --with-zlib --with-sqlite3 \
		--with-fpm-user=php-fpm --with-fpm-group=php-fpm \
		--disable-cgi --disable-phpdbg --disable-rpath
	make
}

install_extension_ini()
{
	printf 'extension=%s.so\n' "$1" > "$PKGDEST/etc/php85/conf.d/20_$2.ini"
}

recipe_install()
{
	make INSTALL_ROOT="$PKGDEST" install
	install -d -m 0755 "$PKGDEST/etc/php85/conf.d" \
		"$PKGDEST/etc/php85/php-fpm.d" "$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system" \
		"$PKGDEST/var/log/php85"
	install -m 0644 php.ini-production "$PKGDEST/etc/php85/php.ini"
	# Drop upstream's .default leftover; we ship a real php-fpm.conf.
	rm -f "$PKGDEST/etc/php85/php-fpm.conf.default"
	install -m 0644 "$RECIPE_DIR/files/php-fpm.conf" \
		"$PKGDEST/etc/php85/php-fpm.conf"
	install -m 0644 "$RECIPE_DIR/files/www.conf" \
		"$PKGDEST/etc/php85/php-fpm.d/www.conf"
	install -m 0755 "$RECIPE_DIR/files/php-fpm.initd" \
		"$PKGDEST/etc/init.d/php-fpm85"
	install -m 0644 "$RECIPE_DIR/files/php-fpm85.service" \
		"$PKGDEST/usr/lib/systemd/system/php-fpm85.service"
	printf 'zend_extension=opcache.so\nopcache.enable=1\nopcache.enable_cli=0\n' \
		> "$PKGDEST/etc/php85/conf.d/00_opcache.ini"
	install_extension_ini mysqli mysqli
	install_extension_ini pdo_mysql pdo_mysql
	install_extension_ini pdo_sqlite pdo_sqlite
	install_extension_ini curl curl
	install_extension_ini zip zip
	install_extension_ini mbstring mbstring
	install_extension_ini dom xml
	printf 'extension=simplexml.so\n' \
		>> "$PKGDEST/etc/php85/conf.d/20_xml.ini"
	install_extension_ini xmlreader xmlreader
	install_extension_ini xmlwriter xmlwriter
}

#!/bin/sh

pkgname=php85
pkgver=8.5.10
# 8.5.10 complete-runtime monolith: CLI + FPM + OPcache + the full useful
# shared-extension set in one package. php85 IS the default Saphira PHP,
# so it owns the unversioned php/php-fpm command names as well.
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="PHP 8.5 language runtime: CLI, FPM, opcache and shared extensions"
license="PHP-3.01"
origin=php85
repo=main
url=https://www.php.net/
source=https://www.php.net/distributions/php-8.5.10.tar.xz
sha256=6a8bebaa4d5a979a38db29a9373e9851f60c6b11f72172c585947e78f3081957

# Required runtime closure, proven from the built payload (readelf -d in
# recipe_install fails closed on any unresolved SONAME):
#   base binary (static): openssl, zlib, sqlite3, libargon2, readline
#   shared extensions: curl, libzip, oniguruma, icu, libpq, openldap,
#     gd, gettext, libsodium, bzip2, libxml2, sqlite
# mysqlnd carries no client library (asserted: no libmysqlclient in any
# NEEDED). Database SERVER packages must never appear here: PHP is a
# client of those facilities, not their owner.
depends="
    bzip2
    curl
    gd
    gettext
    icu
    libargon2
    libpq
    libxml2
    libzip
    libsodium
    oniguruma
    openldap
    openssl
    readline
    sqlite
    zlib
"

makedepends="
    binutils
    bzip2-dev
    curl-dev
    gcc
    gawk
    gd-dev
    gettext-dev
    icu-dev
    libargon2-dev
    libpq
    libxml2-dev
    libzip-dev
    libsodium-dev
    musl-fts-dev
    make
    oniguruma-dev
    openldap-dev
    openssl-dev
    pkgconf
    readline-dev
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
	# (upstream only leaves php-fpm.conf.default). OPcache is
	# always-on and built into the binaries since PHP 8.4: there is no
	# --enable-opcache switch anymore (configure warns it unrecognized)
	# and no shared opcache.so target exists, so the ini below carries
	# settings only, never a zend_extension line.
	#
	# --program-suffix=85 yields php85, php-fpm85, phpize85,
	# php-config85; recipe_install adds the unversioned default names.
	#
	# Deliberately off: cgi (FPM covers server use), phpdbg, oci8/odbc/
	# firebird/imap/snmp/tidy/pspell (backing stacks absent in-tree -
	# each a named follow-up port, not a silent drop), ffi (new attack
	# surface, needs its own review).
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--program-suffix=85 \
		--with-config-file-path=/etc/php85 \
		--with-config-file-scan-dir=/etc/php85/conf.d \
		--enable-cli --enable-fpm \
		--with-mysqli=shared,mysqlnd \
		--with-pdo-mysql=shared,mysqlnd --with-pdo-sqlite=shared \
		--with-pgsql=shared --with-pdo-pgsql=shared \
		--with-ldap=shared \
		--with-curl=shared --with-zip=shared --enable-mbstring=shared \
		--with-bz2=shared --enable-intl=shared --enable-gd=shared \
		--enable-exif=shared --enable-ftp=shared \
		--enable-sockets=shared --enable-pcntl=shared \
		--with-gettext=shared --with-sodium=shared \
		--enable-dom=shared --enable-simplexml=shared \
		--enable-xml=shared --enable-xmlreader=shared --enable-xmlwriter=shared \
		--enable-calendar --enable-sysvmsg --enable-sysvsem --enable-sysvshm \
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
	# Rotation fragment (logrotate.d convention): several FPM
	# instances share these paths, so copytruncate.
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/php-fpm" \
		"$PKGDEST/etc/logrotate.d/php-fpm"
	# Default command names: php85 is the distro-default PHP. Relative
	# symlinks; no alternatives framework (no parallel default needed).
	ln -s php85 "$PKGDEST/usr/bin/php"
	ln -s php-fpm85 "$PKGDEST/usr/sbin/php-fpm"
	# phpize85/php-config85 ride in main, not -dev: the worker only
	# splits fixed path classes (include, cmake, .a/.pc/dev links) and
	# cannot relocate /usr/bin helpers (gcc precedent: dev tools ship
	# with the compiler package). Their unversioned defaults live here
	# beside them.
	ln -s phpize85 "$PKGDEST/usr/bin/phpize"
	ln -s php-config85 "$PKGDEST/usr/bin/php-config"
	printf 'opcache.enable=1\nopcache.enable_cli=0\n' \
		> "$PKGDEST/etc/php85/conf.d/00_opcache.ini"
	# Built-in accelerator proof: with no shared target, the setting
	# lines above are only meaningful if OPcache compiled in. Ask the
	# just-built CLI directly (perl-recipe precedent: validate the
	# product, not the file list). Plain grep (no -q): under the
	# worker's pipefail, grep -q quits early and the producer dies of
	# SIGPIPE, failing the pipeline despite a match.
	"$SRC/sapi/cli/php" -m | grep -i 'Zend OPcache' > /dev/null || \
		{ printf 'php85: OPcache not compiled in\n' >&2; exit 1; }
	install_extension_ini mysqli mysqli
	install_extension_ini pdo_mysql pdo_mysql
	install_extension_ini pdo_sqlite pdo_sqlite
	install_extension_ini pgsql pgsql
	install_extension_ini pdo_pgsql pdo_pgsql
	install_extension_ini ldap ldap
	install_extension_ini curl curl
	install_extension_ini zip zip
	install_extension_ini mbstring mbstring
	install_extension_ini bz2 bz2
	install_extension_ini intl intl
	install_extension_ini gd gd
	install_extension_ini exif exif
	install_extension_ini ftp ftp
	install_extension_ini sockets sockets
	install_extension_ini pcntl pcntl
	install_extension_ini gettext gettext
	install_extension_ini sodium sodium
	install_extension_ini dom xml
	printf 'extension=simplexml.so\n' \
		>> "$PKGDEST/etc/php85/conf.d/20_xml.ini"
	install_extension_ini xmlreader xmlreader
	install_extension_ini xmlwriter xmlwriter
	# Fail-closed ELF dependency proof: every DT_NEEDED entry in the
	# shipped payload must resolve inside the build root (which carries
	# exactly the repository closure). Any unresolved SONAME aborts the
	# package here instead of shipping another unrunnable php.
	#
	# The libargon2 incident lock: the base binary is built
	# --with-password-argon2, so libargon2.so.1 MUST be linked.
	readelf -d "$PKGDEST/usr/bin/php85" | grep -q 'libargon2\.so' ||
		{ printf 'php85: libargon2 missing from php85 DT_NEEDED\n' >&2; exit 1; }
	payload_elfs="$PKGDEST/usr/bin/php85 $PKGDEST/usr/sbin/php-fpm85"
	payload_elfs="$payload_elfs $(find "$PKGDEST/usr/lib" -name '*.so' 2>/dev/null)"
	for elf in $payload_elfs; do
		for needed in $(readelf -d "$elf" 2>/dev/null |
			sed -n 's/.*NEEDED.*\[\(.*\)\].*/\1/p'); do
			case $needed in
				libc.so*|ld-musl-*) continue ;;
			esac
			if [ ! -e "/lib/$needed" ] && [ ! -e "/usr/lib/$needed" ]; then
				printf 'php85: unresolved %s (needed by %s)\n' \
					"$needed" "$elf" >&2
				exit 1
			fi
			# Backend servers must never leak into the linkage: mysqlnd
			# carries no client library, and no slapd/server objects.
			case $needed in
				*libmysqlclient*|*slapd*|*libmysqld*)
					printf 'php85: forbidden %s (needed by %s)\n' \
						"$needed" "$elf" >&2
					exit 1
					;;
			esac
		done
	done
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# php-fpm:103 owns the corrected runtime dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	# r2: php-fpm runtime /run/php-fpm85 -> /var/run/php-fpm85
	# (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/php85" \
		"$PKGDEST/usr/share/saphira/fhs.d/php85"
	# Runtime identity declaration: php-fpm:103 required by the shipped
	# pool config. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/php85" \
		"$PKGDEST/usr/share/saphira/accounts.d/php85"
}

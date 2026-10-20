#!/bin/sh
pkgname=asterisk
pkgver=23.5.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Asterisk open source PBX and telephony engine (PJSIP/IAX2 IP-PBX)'
# Upstream Asterisk licensing, verified from the 23.5.0 source tree
# (LICENSE/COPYING plus per-file headers): GPLv2-only with the
# documented Asterisk exceptions - Sangoma dual-licensing option,
# OpenSSL/OpenH323/UniMRCP/UW-IMAP link exception, and the AMI/AGI/ARI
# protocol-use grant (external managers may use those protocols under
# any licence). No SPDX exception identifier exists for these in
# Saphira packaging, so the field carries the base licence and this
# comment plus the shipped LICENSE/COPYING carry the exceptions.
license='GPL-2.0-only'
origin=asterisk
repo=saphira
url=https://www.asterisk.org/
source=https://github.com/asterisk/asterisk/releases/download/23.5.0/asterisk-23.5.0.tar.gz
sha256=8ed3a237e6d8dff94a09527a83143530b5afcc1aee73fa7b85c069bda507adac

# Runtime closure, read off DT_NEEDED of the proven staged build
# (binary + all 310 modules): sqlite3 (astdb/cdr), curl (res_curl
# family), openssl (TLS/SRTP/crypto), pjproject (all PJSIP modules),
# unbound (res_resolver_unbound), lua54 (pbx_lua), uuid (core),
# libedit (CLI), libcap/libcrypt (core), xml2 (xmldoc), zlib (http),
# gcc-libs (libstdc++/libgcc_s for the binary and pj consumers).
depends="
    curl
    gcc-libs
    jansson
    libcap
    libedit
    libxcrypt
    libxml2
    lua54
    openssl
    pjproject
    sqlite
    unbound
    util-linux
    zlib
"

makedepends="
    binutils
    bison
    flex
    gawk
    gcc
    make
    pkgconf
    saphira-linux-uapi-headers

    curl-dev
    jansson-dev
    libcap-dev
    libedit-dev
    libxml2-dev
    lua54-dev
    ncurses-dev
    openssl-dev
    pjproject-dev
    sqlite-dev
    unbound-dev
    util-linux-dev
    zlib-dev
"

# Single APK by design: chan_pjsip/chan_iax2 and all res_pjsip modules
# ship in this package (they are in-tree, not separate upstreams). No
# -sip/-iax2 splits, no -doc split (four small man pages stay).
subpackages=""

recipe_build()
{
	# Six musl fixes, each proven required on Saphira (staged
	# 23.5.0 build + live 322-module boot, plus the live-gate
	# #include-heavy boot for 0006); all preserve upstream
	# structure and are upstreamable as-is:
	#  0001: __P() fallback (musl ships no <sys/cdefs.h>)
	#  0002: recursive module_list.lock (loader re-enters register)
	#  0003: recursive conlock (documented REQUIRED recursive, #17643)
	#  0004: recursive chan_unistim devicelock (reload nests bookmark)
	#  0005: recursive res_prometheus scrape_lock (load nests unregister)
	#  0006: recursive config cfmtime_head (include recheck nests;
	#  without it any re-read of an unchanged file with #includes
	#  deadlocks the loader — hits all #include-heavy configs)
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/asterisk-23.5.0.tar.gz"
	cd "$SRC"
	for p in \
		0001-ast_expr2-musl-sys-cdefs-__P.patch \
		0002-loader-recursive-module_list-lock.patch \
		0003-pbx-recursive-conlock.patch \
		0004-unistim-recursive-devicelock.patch \
		0005-prometheus-recursive-scrape_lock.patch \
		0006-config-recursive-cfmtime_head.patch \
	; do
		patch -p1 < "$RECIPE_DIR/files/$p"
	done
	# PJSIP comes from the Saphira pjproject package (system model):
	# bare --with-pjproject resolves libpjproject.pc from the clean
	# root (pjproject-dev); no bundled tarball, no externals cache,
	# no network fetch, no libasteriskpj.so.2. Hardware telephony and
	# unused SQL CDR backends stay off (DAHDI later becomes
	# asterisk-dahdi if ever needed; none of these are blockers).
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--without-pjproject-bundled \
		--with-pjproject \
		--without-dahdi \
		--without-pri \
		--without-ss7 \
		--without-openr2 \
		--without-tonezone \
		--without-bluetooth \
		--without-jack \
		--without-portaudio \
		--without-mysqlclient \
		--without-postgres \
		--without-unixodbc \
		--without-tds
	# Deterministic module selection (proven set): hardware/extra
	# modules off; chan_pjsip + chan_iax2 stay enabled; res_srtp and
	# friends stay dependency-gated (libsrtp not in Saphira yet).
	make menuselect
	./menuselect/menuselect \
		--disable chan_dahdi \
		--disable chan_mobile \
		--disable chan_ooh323 \
		--disable format_mp3 \
		--disable res_config_mysql \
		--disable codec_dahdi \
		--disable res_timing_dahdi \
		menuselect.makeopts menuselect-tree
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	cd "$SRC"
	DESTDIR="$PKGDEST" make install
	DESTDIR="$PKGDEST" make samples
	# Saphira-owned directory map (runtime state through /run);
	# installed after samples so it wins over the template default.
	install -D -m 0644 "$RECIPE_DIR/files/asterisk.conf" \
		"$PKGDEST/etc/asterisk/asterisk.conf"
	# Dual init: both formats ship unconditionally, neither is enabled
	# at install time (enabling is a profile decision, never automatic).
	install -D -m 0644 "$RECIPE_DIR/files/asterisk.service" \
		"$PKGDEST/usr/lib/systemd/system/asterisk.service"
	install -D -m 0755 "$RECIPE_DIR/files/asterisk.initd" \
		"$PKGDEST/etc/init.d/asterisk"
	# Volatile /run/asterisk for the unprivileged daemon (systemd
	# RuntimeDirectory covers systemd boots; tmpfiles.d covers the
	# rest; OpenRC checkpath covers service start).
	install -D -m 0644 "$RECIPE_DIR/files/asterisk.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/asterisk.conf"
	# Service identity: asterisk:asterisk, fixed UID/GID 154.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/asterisk" \
		"$PKGDEST/usr/share/saphira/accounts.d/asterisk"
	# Log rotation owns its fragment (daemon reopens on logger reload).
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/asterisk" \
		"$PKGDEST/etc/logrotate.d/asterisk"
	# Deliberate non-shipments (all verified in Phase 0):
	# - upstream socket units (AMI/HTTP/CLI socket activation): niche,
	#   not part of the service contract; plain service only.
	# - asterisk-malloc-trim service/timer: malloc_trim() is a GNU
	#   extension absent on musl; the unit would only fail.
	# - no update-rc.d/post-install handling: `make install` under
	#   DESTDIR invokes neither (verified), and `make config` (which
	#   would) is never run. Nothing to neutralise beyond not running it.
	# - /usr/sbin/sendmail default in voicemail/minivm: left as-is; with
	#   no MTA installed voicemail-to-email degrades to a logged
	#   warning. No fake sendmail, no extra dependency.
	# - seed voicemail INBOX (default/1234): upstream read-only seed
	#   content, left root-owned; per-mailbox dirs are daemon-created.
}

#!/bin/sh

pkgname=freeradius
pkgver=3.2.10
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="RADIUS authentication, authorization and accounting server"
license="GPL-2.0-or-later"
origin=freeradius
repo=main
url=https://freeradius.org/
source=https://github.com/FreeRADIUS/freeradius-server/releases/download/release_3_2_10/freeradius-server-3.2.10.tar.gz
sha256=40e0cdfdcceb22cf0acb79bc29cf7c32995466a61fda09445ce5220608a55afd

depends="
    curl
    libpcap
    openssl
    pcre2
    sqlite
    talloc
"

makedepends="
    binutils
    curl-dev
    gcc
    gdbm-dev
    autoconf
    automake
    json-c-dev
    libpcap-dev
    libtool
    make
    openssl-dev
    pcre2-dev
    perl
    python3-dev
    sqlite-dev
    talloc-dev
"

# rlm_sql_postgresql stays disabled (postgresql-client dev payload with
# pg_config/libpq headers not yet verified); rlm_sql_mysql awaits a
# mariadb r1+ (client config tool + -dev headers - mariadb is r0-only
# in the archive, nothing live). --with-systemd=no is correct with the
# shipped Type=simple unit (no sd_notify linkage needed); the openrc
# initd and the systemd unit ship from this single build - no split
# builds. --with-dhcp is upstream-default but stated explicitly.
# --enable-strict-dependencies stays off: it would demand oracle/mongo
# era modules nothing in the tree can satisfy.
# In-tree build: upstream's module system assumes srcdir==builddir
# (rlm_cache/configure cats relative 'stable' and symlinks
# ../../../install-sh - both break under a VPATH BUILDDIR and fail the
# whole build). $SRC is per-build scratch already dirtied by autoreconf,
# so in-tree is safe here.
recipe_build()
{
	cd "$SRC"
	autoreconf -fi .
	./configure --prefix=/usr \
		--sysconfdir=/etc --localstatedir=/var \
		--runstatedir=/run --with-raddbdir=/etc/raddb \
		--with-logdir=/var/log/radius --with-systemd=no \
		--disable-option-checking \
		--with-dhcp --with-pcre --with-openssl \
		--without-rlm_sql_postgresql \
		--enable-reproducible-builds
	make
}

recipe_install()
{
	make -C "$SRC" R="$PKGDEST" install
	rm -rf "$PKGDEST/usr/bin"
	rm -f "$PKGDEST/usr/sbin/radmin" "$PKGDEST/usr/sbin/raddebug"
	sed -i 's/^[#[:space:]]*user = radius/user = radius/' \
		"$PKGDEST/etc/raddb/radiusd.conf"
	sed -i 's/^[#[:space:]]*group = radius/group = radius/' \
		"$PKGDEST/etc/raddb/radiusd.conf"
	install -D -m 0755 "$RECIPE_DIR/files/freeradius.initd" \
		"$PKGDEST/etc/init.d/freeradius"
	install -D -m 0644 "$RECIPE_DIR/files/freeradius.service" \
		"$PKGDEST/usr/lib/systemd/system/freeradius.service"
	install -d -m 0750 "$PKGDEST/var/lib/radius" \
		"$PKGDEST/var/log/radius"
	# Runtime identity declaration: radius:121 required by the shipped
	# service unit. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	# r2: fragment added (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/freeradius" \
		"$PKGDEST/usr/share/saphira/accounts.d/freeradius"
	# Upstream's master dictionary uses ~230 bare relative $INCLUDEs
	# (dictionary.*). Relative names resolve against the process context
	# (/etc/raddb on a running daemon) instead of the dictdir, killing
	# the load at the first hit (chillispot line 186). Absolute paths
	# resolve identically when the base is already correct, and
	# correctly when it is not - so rewrite them all, with a count
	# guard against silent upstream format drift.
	sed -i 's|^\$INCLUDE \(dictionary\.[^ /]*\)$|$INCLUDE /usr/share/freeradius/\1|' \
		"$PKGDEST/usr/share/freeradius/dictionary"
	[ "$(grep -c '^\$INCLUDE /usr/share/freeradius/dictionary\.' \
		"$PKGDEST/usr/share/freeradius/dictionary")" -ge 200 ] ||
		{ printf 'freeradius: dictionary INCLUDE rewrite broke\n' >&2; exit 1; }
	# NOTE: raddb ownership is NOT normalized here. makepkg flattens
	# payload ownership to 0:0 at construction, so recipe-side chown
	# would be dead code. Upstream installs raddb 750/640; radiusd runs
	# as radius:radius and must read it (the pre-r3 "Permission denied"
	# on mods-config/files/authorize). Ownership converges at service
	# start in freeradius.initd (start_pre) and freeradius.service
	# (ExecStartPre, root-privileged) - which also heals pre-r3 installs.
	# r3: gdbm/json-c/libpcap features on (+libpcap runtime for radsniff).
}

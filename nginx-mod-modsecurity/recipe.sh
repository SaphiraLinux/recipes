#!/bin/sh

# ModSecurity v3 nginx connector 1.0.4 (dynamic module only).
#
# ModSecurity v3 deliberately ships no nginx integration; this is
# the module that connects nginx to libmodsecurity. Built against
# the EXACT nginx source the nginx package uses (same tarball, same
# ./configure flag set plus --add-dynamic-module), then `make
# modules` - nginx itself was built --with-compat, which is what
# makes this out-of-tree .so loadable.
#
# ABI coupling is explicit and fails closed: the nginx source is
# referenced from the nginx recipe's files/ by exact basename, so
# an nginx source upgrade breaks this build loudly until the
# pairing is re-validated here (never silently mix nginx N with a
# module configured against N-1). The nginx package must not ship
# this .so itself (split ownership would collide at the gate); the
# install below asserts exactly one module ships and nothing else.
#
# Release tarball, not a branch pin: 1.0.4 is the current connector
# release for the v3 engine line.

pkgname=nginx-mod-modsecurity
pkgver=1.0.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ModSecurity v3 connector dynamic module for nginx"
license=Apache-2.0
origin=nginx-mod-modsecurity
repo=saphira
url=https://github.com/owasp-modsecurity/ModSecurity-nginx
source=https://github.com/owasp-modsecurity/ModSecurity-nginx/releases/download/v1.0.4/ModSecurity-nginx-v1.0.4.tar.gz
sha256=6bdc7570911be884c1e43aaf85046137f9fde0cfa0dd4a55b853c81c45a13313

# Runtime: the nginx binary/module dir plus the engine library the
# .so links (libmodsecurity.so.3).
depends="
    modsecurity
    nginx
"

# Full nginx configure closure (every --with/--add flag below is
# probed at configure time even though only one module ships) plus
# the engine headers the connector builds against.
makedepends="
    binutils
    brotli-dev
    gcc
    gd-dev
    libgeoip
    libmaxminddb-dev
    libxslt-dev
    make
    modsecurity-dev
    openssl-dev
    pcre2-dev
    perl
    zlib-dev
"

recipe_build()
{
	# Exact nginx source coupling (see header): same bytes the
	# nginx-1.30.4 package configures. Fail closed on any drift.
	nginx_src="$RECIPE_DIR/../nginx/files/nginx-1.30.4.tar.gz"
	nginx_sha256=4261dc90e9e47c1c4041276e9aaa3d48ebe2e664f728e14fa95ae6c67d57a08b
	echo "$nginx_sha256  $nginx_src" | sha256sum -c -
	echo "$sha256  $RECIPE_DIR/files/ModSecurity-nginx-v1.0.4.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" -xf "$nginx_src"
	mv "$SRC"/nginx-1.30.4 "$SRC/nginx"
	mkdir -p "$SRC/nginx/modules"
	tar --no-same-owner -C "$SRC/nginx/modules" -xf "$RECIPE_DIR/files/ModSecurity-nginx-v1.0.4.tar.gz"
	mv "$SRC/nginx/modules"/ModSecurity-nginx-v1.0.4 "$SRC/nginx/modules/modsecurity"
	cd "$SRC/nginx"
	# Flag set mirrors the nginx recipe exactly (plus the connector
	# module); any flag drift between the two recipes risks a
	# module the binary refuses to load - keep them in lockstep.
	# layout-exception: same custom nginx configure dialect as nginx
	# (deliberate /var/lib/nginx prefix, every path explicit).
	./configure \
		--prefix=/var/lib/nginx \
		--sbin-path=/usr/sbin/nginx \
		--modules-path=/usr/lib/nginx/modules \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--pid-path=/var/run/nginx/nginx.pid \
		--lock-path=/var/run/nginx/nginx.lock \
		--http-client-body-temp-path=/var/lib/nginx/client_body \
		--http-proxy-temp-path=/var/lib/nginx/proxy \
		--http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
		--with-compat --with-file-aio --with-threads --with-pcre-jit \
		--with-http_ssl_module --with-http_v2_module --with-http_v3_module \
		--with-http_realip_module --with-http_gzip_static_module \
		--with-http_gunzip_module --with-http_stub_status_module \
		--with-http_auth_request_module --with-http_secure_link_module \
		--with-http_slice_module \
		--with-http_addition_module \
		--with-http_dav_module \
		--with-http_degradation_module \
		--with-http_flv_module \
		--with-http_mp4_module \
		--with-http_random_index_module \
		--with-http_sub_module \
		--with-http_geoip_module=dynamic \
		--with-http_image_filter_module=dynamic \
		--with-http_perl_module=dynamic \
		--with-mail --with-mail_ssl_module \
		--with-http_xslt_module=dynamic \
		--add-dynamic-module="$SRC/nginx/modules/modsecurity" \
		--with-stream=dynamic --with-stream_ssl_module \
		--with-stream_realip_module --with-stream_ssl_preread_module \
		--with-cc-opt="${CPPFLAGS-} ${CFLAGS-} -Wno-error=unused-but-set-variable" --with-ld-opt="${LDFLAGS-}"
	# Modules only: the nginx binary and its other modules belong
	# to the nginx package and must never be rebuilt here.
	make -j${JOBS:-$(nproc)} modules
	test -f "$SRC/nginx/objs/ngx_http_modsecurity_module.so" ||
		{ echo "ERROR: modsecurity module missing after build" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0644 "$SRC/nginx/objs/ngx_http_modsecurity_module.so" \
		"$PKGDEST/usr/lib/nginx/modules/ngx_http_modsecurity_module.so"
	# Split ownership: exactly one .so ships here, everything else
	# (binary, sibling modules, config) stays with nginx. Any
	# second .so in staging is a split bug - fail loudly.
	test "$(find "$PKGDEST/usr/lib/nginx/modules" -name '*.so' | wc -l)" -eq 1 ||
		{ echo "ERROR: module payload must contain exactly one .so" >&2; return 1; }
}

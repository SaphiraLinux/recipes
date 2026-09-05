#!/bin/sh

pkgname=nginx
pkgver=1.30.4
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira webDragon HTTP server and reverse proxy"
license="BSD-2-Clause"
origin=nginx
repo=main
url=https://nginx.org/
source=https://nginx.org/download/nginx-1.30.4.tar.gz
sha256=4261dc90e9e47c1c4041276e9aaa3d48ebe2e664f728e14fa95ae6c67d57a08b

depends="
    brotli
    libmaxminddb
    libxslt
    pcre2
    openssl
    zlib
"

makedepends="
    binutils
    brotli-dev
    gcc
    libmaxminddb-dev
    libxslt-dev
    make
    openssl-dev
    pcre2-dev
    zlib-dev
"

subpackages="
    $pkgname-doc
"

recipe_build()
{
	# Dual-format service package: systemd unit under /usr/lib/systemd/system,
	# OpenRC script under /etc/init.d (see files/). Third-party dynamic
	# modules headers-more (v0.34), geoip2 (v3.4) and brotli are enabled,
	# plus the zero-dependency static set (addition, dav, degradation,
	# flv, mp4, random_index, sub), mail proxy (+ssl) and dynamic xslt;
	# http v2/v3 (quic), ssl, realip, slice and the stream set were
	# already on. perl/image_filter stay deferred (no perl-dev/gd yet;
	# geoip v1 superseded by geoip2).
	# ngx_brotli has no release tarball: pinned to upstream master commit
	# a71f9312c2deb28875acc7bacfdd5695a111aa53 (sha256 below covers the
	# exact bytes; not a floating branch).
	headers_more_sha256=0c0d2ced2ce895b3f45eb2b230cd90508ab2a773299f153de14a43e44c1209b3
	geoip2_sha256=ad72fc23348d715a330994984531fab9b3606e160483236737f9a4a6957d9452
	ngx_brotli_sha256=1d21be34f3b7b6d05a8142945e59b3a47665edcdfe0f3ee3d3dbef121f90c08c
	echo "$headers_more_sha256  $RECIPE_DIR/files/headers-more-0.34.tar.gz" | sha256sum -c -
	echo "$geoip2_sha256  $RECIPE_DIR/files/ngx-geoip2-3.4.tar.gz" | sha256sum -c -
	echo "$ngx_brotli_sha256  $RECIPE_DIR/files/ngx-brotli-a71f931.tar.gz" | sha256sum -c -
	mkdir -p "$SRC/modules"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/headers-more-0.34.tar.gz"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/ngx-geoip2-3.4.tar.gz"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/ngx-brotli-a71f931.tar.gz"
	mv "$SRC/modules"/headers-more-nginx-module-0.34 "$SRC/modules/headers-more"
	mv "$SRC/modules"/ngx_http_geoip2_module-3.4 "$SRC/modules/geoip2"
	mv "$SRC/modules"/ngx_brotli-a71f9312c2deb28875acc7bacfdd5695a111aa53 "$SRC/modules/ngx_brotli"
	# ngx_brotli builds against brotli sources at deps/brotli (headers);
	# it links the system libbrotlienc at runtime. Stage the exact
	# vendored brotli bytes so headers match the packaged library.
	# The module tarball carries its git submodule path as an empty
	# dir; clear it or mv nests one level too deep and configure
	# fails to find deps/brotli/c.
	mkdir -p "$SRC/modules/ngx_brotli/deps"
	tar --no-same-owner -C "$SRC/modules/ngx_brotli/deps" -xf "$RECIPE_DIR/../brotli/files/brotli-1.2.0.tar.gz"
	rm -rf "$SRC/modules/ngx_brotli/deps/brotli"
	mv "$SRC/modules/ngx_brotli/deps/brotli-1.2.0" "$SRC/modules/ngx_brotli/deps/brotli"
	./configure \
		--prefix=/var/lib/nginx \
		--sbin-path=/usr/sbin/nginx \
		--modules-path=/usr/lib/nginx/modules \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--pid-path=/run/nginx/nginx.pid \
		--lock-path=/run/nginx/nginx.lock \
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
		--with-mail --with-mail_ssl_module \
		--with-http_xslt_module=dynamic \
		--add-dynamic-module="$SRC/modules/headers-more" \
		--add-dynamic-module="$SRC/modules/geoip2" \
		--add-dynamic-module="$SRC/modules/ngx_brotli" \
		--with-stream=dynamic --with-stream_ssl_module \
		--with-stream_realip_module --with-stream_ssl_preread_module \
		--with-cc-opt="${CPPFLAGS-} ${CFLAGS-}" --with-ld-opt="${LDFLAGS-}"
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	rm -f "$PKGDEST/etc/nginx/nginx.conf.default"
	install -d -m 0755 \
		"$PKGDEST/etc/init.d" \
		"$PKGDEST/usr/lib/systemd/system" \
		"$PKGDEST/usr/lib/tmpfiles.d" \
		"$PKGDEST/etc/nginx/conf.d" \
		"$PKGDEST/var/log/nginx" \
		"$PKGDEST/var/lib/nginx/client_body" \
		"$PKGDEST/var/lib/nginx/proxy" \
		"$PKGDEST/var/lib/nginx/fastcgi" \
		"$PKGDEST/var/www/localhost/htdocs"
	install -m 0644 "$RECIPE_DIR/files/nginx.service" \
		"$PKGDEST/usr/lib/systemd/system/nginx.service"
	install -m 0755 "$RECIPE_DIR/files/nginx.initd" \
		"$PKGDEST/etc/init.d/nginx"
	install -m 0644 "$RECIPE_DIR/files/nginx.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/nginx.conf"
	install -m 0644 "$RECIPE_DIR/files/nginx.conf" \
		"$PKGDEST/etc/nginx/nginx.conf"
	install -m 0644 "$RECIPE_DIR/files/nginx-default.conf" \
		"$PKGDEST/etc/nginx/conf.d/default.conf"
	printf '<h1>Saphira webDragon seed</h1>\n' > \
		"$PKGDEST/var/www/localhost/htdocs/index.html"
}

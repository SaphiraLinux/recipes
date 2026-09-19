#!/bin/sh

pkgname=nginx
pkgver=1.30.4
# r7: connector unbundled (r6 was drafted but never published):
# the ModSecurity v3 nginx connector now ships as the separate
# nginx-mod-modsecurity package, built against this exact source
# tree - nginx no longer carries the .so, the modsecurity-dev
# build closure, or the WAF wiring examples (those live in
# saphira-nginx-waf). Removing the bundled .so is a payload
# change, hence the new revision.
# r5: Arch-parity dynamic module set (all ten reference families):
# brotli, cache_purge (new, vendored), geoip v1 (new, libgeoip),
# geoip2, headers-more, image_filter (new, gd), memc (new, vendored),
# perl (new, static libperl baked in - no perl rebuild needed),
# stream set, xslt. sub_filter mandatory for AZ2 realtime-price
# rewriting (kept static, always present). mail stays static.
# r8: own the nginx logrotate fragment (migrated out of the
# logrotate package per the logrotate.d convention: the service
# recipe owns its reload semantics).
pkgrel=10
# r10: proxy/fastcgi temp dirs ship 0700 (homer recon carries 0700;
# these hold transient response bodies, so world-readable temp
# storage was never intended). client_body and the other temp
# paths keep 0755 (no signal either way). Payload change, bumps.
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
    gd
    libgeoip
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
    gd-dev
    libgeoip
    libmaxminddb-dev
    libxslt-dev
    make
    openssl-dev
    pcre2-dev
    perl
    zlib-dev
"

subpackages="
    $pkgname-doc
"

recipe_build()
{
	# Dual-format service package: systemd unit under /usr/lib/systemd/system,
	# OpenRC script under /etc/init.d (see files/). Third-party dynamic
	# modules headers-more (v0.34), geoip2 (v3.4), brotli, memc (v0.21)
	# and cache_purge (v2.3) are enabled, plus geoip v1, image_filter
	# and perl as dynamic modules, the zero-dependency static set
	# (addition, dav, degradation, flv, mp4, random_index, sub),
	# mail proxy (+ssl) and dynamic xslt; http v2/v3 (quic), ssl,
	# realip, slice and the stream set were already on.
	# perl links libperl into its .so: perl 5.44 ships shared
	# libperl.so (preferred by the shared link) over a PIC static
	# archive fallback. =dynamic support for geoip/image_filter/perl
	# verified against upstream auto/options.
	# -Wno-error=unused-but-set-variable: the vendored third-party
	# modules are 2023-era code (headers-more 0.34 hit first) and gcc
	# 16 warns on idioms that were silent then. One narrow downgrade
	# appended after nginx's own -Werror (later flag wins for that
	# class only); -Werror stays intact for everything else, including
	# nginx core. Extend the list on evidence if sibling modules trip
	# their own classes - do not blanket -Wno-error.
	headers_more_sha256=0c0d2ced2ce895b3f45eb2b230cd90508ab2a773299f153de14a43e44c1209b3
	geoip2_sha256=ad72fc23348d715a330994984531fab9b3606e160483236737f9a4a6957d9452
	ngx_brotli_sha256=1d21be34f3b7b6d05a8142945e59b3a47665edcdfe0f3ee3d3dbef121f90c08c
	memc_sha256=6eb85655475506c577f86c0c6d902419000f66876215461e10411206a4dc554e
	cache_purge_sha256=cb7d5f22919c613f1f03341a1aeb960965269302e9eb23425ccaabd2f5dcbbec
	echo "$headers_more_sha256  $RECIPE_DIR/files/headers-more-0.34.tar.gz" | sha256sum -c -
	echo "$geoip2_sha256  $RECIPE_DIR/files/ngx-geoip2-3.4.tar.gz" | sha256sum -c -
	echo "$ngx_brotli_sha256  $RECIPE_DIR/files/ngx-brotli-a71f931.tar.gz" | sha256sum -c -
	echo "$memc_sha256  $RECIPE_DIR/files/memc-0.21.tar.gz" | sha256sum -c -
	echo "$cache_purge_sha256  $RECIPE_DIR/files/cache-purge-2.3.tar.gz" | sha256sum -c -
	mkdir -p "$SRC/modules"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/headers-more-0.34.tar.gz"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/ngx-geoip2-3.4.tar.gz"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/ngx-brotli-a71f931.tar.gz"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/memc-0.21.tar.gz"
	tar --no-same-owner -C "$SRC/modules" -xf "$RECIPE_DIR/files/cache-purge-2.3.tar.gz"
	mv "$SRC/modules"/headers-more-nginx-module-0.34 "$SRC/modules/headers-more"
	mv "$SRC/modules"/ngx_http_geoip2_module-3.4 "$SRC/modules/geoip2"
	mv "$SRC/modules"/ngx_brotli-a71f9312c2deb28875acc7bacfdd5695a111aa53 "$SRC/modules/ngx_brotli"
	mv "$SRC/modules"/memc-nginx-module-0.21 "$SRC/modules/memc"
	mv "$SRC/modules"/ngx_cache_purge-2.3 "$SRC/modules/cache_purge"
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
	# layout-exception: nginx uses its own configure dialect (no GNU
	# dir flags except --prefix, deliberately rooted at
	# /var/lib/nginx); every installed path below is already explicit
	# (--sbin-path, --conf-path, --pid-path, --lock-path, temp paths).
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
		--add-dynamic-module="$SRC/modules/headers-more" \
		--add-dynamic-module="$SRC/modules/geoip2" \
		--add-dynamic-module="$SRC/modules/ngx_brotli" \
		--add-dynamic-module="$SRC/modules/memc" \
		--add-dynamic-module="$SRC/modules/cache_purge" \
		--with-stream=dynamic --with-stream_ssl_module \
		--with-stream_realip_module --with-stream_ssl_preread_module \
		--with-cc-opt="${CPPFLAGS-} ${CFLAGS-} -Wno-error=unused-but-set-variable" --with-ld-opt="${LDFLAGS-}"
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
		"$PKGDEST/var/www/localhost/htdocs"
	# Proxy temp storage holds transient response bodies: 0700.
	install -d -m 0700 \
		"$PKGDEST/var/lib/nginx/proxy" \
		"$PKGDEST/var/lib/nginx/fastcgi"
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
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# nginx:102 owns the corrected runtime dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	# r9: runtime paths /run/nginx -> /var/run/nginx (payload change,
	# revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/nginx" \
		"$PKGDEST/usr/share/saphira/fhs.d/nginx"
	# Runtime identity declaration: nginx:102 required by the shipped
	# server config. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	# r4: fragment added (payload change, revision bumps).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/nginx" \
		"$PKGDEST/usr/share/saphira/accounts.d/nginx"
	# Rotation fragment (logrotate.d convention): nginx holds its
	# logs open, so the fragment reopens rather than copytruncates.
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/nginx" \
		"$PKGDEST/etc/logrotate.d/nginx"
}

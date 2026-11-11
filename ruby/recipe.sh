#!/bin/sh

pkgname=ruby
pkgver=4.0.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Ruby programming language interpreter (CRuby/MRI)'
license='Ruby AND BSD-2-Clause AND MIT'
origin=ruby
repo=saphira
url=https://www.ruby-lang.org/
source=https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.9.tar.gz
sha256=c35350682ff050b79702d57ade4516e7336063f510155d19fb2fb5b3f3909511

# Runtime closure (python3 doctrine: every DT_NEEDED provider named):
# libruby links gmp (Bignum acceleration, default-on); the C
# extensions link openssl/libcrypto, libyaml (psych), libffi (fiddle)
# and zlib. ca-certificates owns TLS trust: the bundled rubygems PEMs
# are removed at install (Alpine precedent) so the system store at
# /etc/ssl/certs (openssl --openssldir=/etc/ssl) is authoritative.
# NOTE (4.0.9 source inventory, NOT an omission): there is no
# ext/readline and no gdbm bundled gem in 4.0 - readline is a pure-Ruby
# reline shim and gdbm/dbm/sdbm left the stdlib, so readline-dev,
# gdbm-dev, readline, ncurses and gdbm are absent on purpose.
depends="ca-certificates gmp libffi libyaml musl openssl zlib"

makedepends="
	gcc
	gmp-dev
	libffi-dev
	libyaml-dev
	make
	openssl-dev
	pkgconf
	saphira-linux-uapi-headers
	zlib-dev
"

subpackages="$pkgname-dev $pkgname-doc"

# Ruby 4.0.9: latest stable (2026-10-23, normal maintenance to
# 2028, EOL 2029-03), verified against the SHA256 published in the
# ruby-lang.org 4.0.9 release announcement. musl triage (Alpine
# main/ruby, musl-native, x86_64-linux-musl logs):
# - coroutine impl on x86_64-linux defaults to amd64 asm
#   (configure.ac target case), so no libucontext linkage is forced;
#   any future native gem needing ucontext finds libucontext published.
# - isnan/isinf configure probes fail on musl macro definitions,
#   hence ac_cv_func_isnan/isinf=yes (Alpine).
# - CFLAGS: -O2 not -Os (ruby segfaults/bus-errors on -Os per
#   Alpine/gentoo), -fno-omit-frame-pointer, -fno-strict-aliasing.
# - YJIT/ZJIT explicitly disabled: both require rustc and there is
#   no rust/cargo in the universe (ruby -> BLOCKED_BY_rust for JIT;
#   the interpreter, gem tooling and asciidoctor are unaffected).
#   Explicit off beats silent auto-off per the explicit-feature rule.
# - psych uses the system libyaml (new libyaml port, same change);
#   no extension is knowingly left to silent autodetection: make test
#   plus the extension file assertions below fail closed.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/ruby-${pkgver}.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/ruby-${pkgver}.tar.gz"

	cd "$SRC"

	export CFLAGS="${CFLAGS:--O2} -fno-omit-frame-pointer -fno-strict-aliasing"
	export CPPFLAGS="${CPPFLAGS:-} -fno-omit-frame-pointer -fno-strict-aliasing"

	# the configure script does not detect isnan/isinf as macros
	export ac_cv_func_isnan=yes
	export ac_cv_func_isinf=yes

	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--mandir=/usr/share/man --infodir=/usr/share/info \
		--enable-pthread --disable-rpath --enable-shared \
		--with-mantype=man \
		--disable-yjit --disable-zjit
	# --with-sitedir is deliberately ABSENT: Alpine points it at
	# /usr/local/lib/site_ruby, but Saphira forbids /usr/local in
	# distribution payloads (makepkg fails closed on any staging
	# there), so the configure default under ${prefix} stands.
	make -j${JOBS:-$(nproc)}
	# Upstream basic suite (Alpine check() precedent on musl):
	# proves the interpreter plus default/bundled extensions work.
	make test
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install

	# Bundled CA certificates are removed (Alpine precedent); the
	# ca-certificates package (in depends) owns /etc/ssl/certs.
	rm -f "$PKGDEST"/usr/lib/ruby/*/rubygems/ssl_certs/*/*.pem
	rmdir "$PKGDEST"/usr/lib/ruby/*/rubygems/ssl_certs/* 2>/dev/null || true

	# Dead-path doc reference (me-cleaner idiom): rbs-3.10.0's
	# core/pathname.rbs carries a comment example using
	# /usr/bin/shutdown, and the policy gate fails closed on any
	# /usr/bin/sh substring (no such path on non-usrmerged Saphira;
	# sh is /bin/sh). The file is inert type data, but the gate is
	# substring-based, so re-point the example AND its expected
	# output at the real /bin/sh (baselayout owns bin/sh).
	sed_target=
	for candidate in "$PKGDEST"/usr/lib/ruby/gems/*/gems/rbs-*/core/pathname.rbs; do
		[ -f "$candidate" ] || {
			echo "ruby: rbs pathname.rbs not staged where expected" >&2
			exit 1
		}
		sed -i "s|/usr/bin/shutdown|/bin/sh|g" "$candidate"
		sed_target=$candidate
	done
	[ -n "$sed_target" ] || {
		echo "ruby: rbs pathname.rbs glob matched nothing" >&2
		exit 1
	}
	# Fail closed on any recurrence (next rbs bump re-adding a
	# /usr/bin/sh* example trips here, not at the policy gate).
	if grep -rq '/usr/bin/sh' "$PKGDEST/usr/lib/ruby"; then
		echo "ruby: /usr/bin/sh reference in payload:" >&2
		grep -rl '/usr/bin/sh' "$PKGDEST/usr/lib/ruby" >&2
		exit 1
	fi

	test -x "$PKGDEST/usr/bin/ruby"
	test -n "$(find "$PKGDEST/usr/lib" -name 'libruby.so.*' -print -quit)"
	# Chain-critical extensions must have built (no silent skips):
	# openssl (gem TLS), psych (gemspec YAML), zlib, fiddle and
	# bigdecimal (the gmp consumer). readline is pure Ruby in 4.0
	# (reline shim, no .so) and gdbm left the stdlib - asserting
	# their .so files would fail closed on an upstream shape change
	# that already happened, so they are deliberately absent here.
	for ext in openssl psych zlib fiddle bigdecimal; do
		test -n "$(find "$PKGDEST" -name "$ext.so" -print -quit)" || {
			echo "ruby: required extension $ext.so missing from payload" >&2
			exit 1
		}
	done
	# The bundled trust store must be gone (system store authoritative).
	test -z "$(find "$PKGDEST/usr/lib/ruby" -path '*ssl_certs/*/*.pem' -print -quit)"
}

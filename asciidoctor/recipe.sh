#!/bin/sh

pkgname=asciidoctor
pkgver=2.0.26
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='AsciiDoc text processor and publishing toolchain'
license='MIT'
origin=asciidoctor
repo=saphira
url=https://asciidoctor.org/
source=https://github.com/asciidoctor/asciidoctor/archive/v2.0.26/asciidoctor-2.0.26.tar.gz
sha256=25c22b934bc0ae2448f2d73d4b2eba0c59e0521cf5e893fb0b0ad54a461bf066

# Pure-Ruby gem (verified: gemspec sets require_paths lib only, no
# extensions; required_ruby_version is commented out upstream, so no
# floor to honor). Built with our ruby port (makedepends), installed
# staged via GEM_HOME so no write escapes $PKGDEST. The man page the
# systemd/cryptsetup doc builds need ships as a file, like BLFS.
depends="ruby"

makedepends="ruby"

subpackages="$pkgname-doc"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/asciidoctor-${pkgver}.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/asciidoctor-${pkgver}.tar.gz"

	cd "$SRC"

	# BLFS notes the 'not a git repository' message here is normal:
	# the gemspec falls back to Dir['**/*'] outside a checkout.
	gem build asciidoctor.gemspec
}

recipe_install()
{
	rbver=$(ruby -e 'print RbConfig::CONFIG["ruby_version"]')
	gemhome="$PKGDEST/usr/lib/ruby/gems/$rbver"
	# GEM_HOME stays staged (installs land in the payload), but
	# GEM_PATH must ALSO see the system default gem dir: asciidoctor
	# requires bundled gems (logger, ...) that live in the ruby
	# package, not in this payload. GEM_PATH replaces the defaults
	# wholesale, so omitting the system dir breaks every require.
	sysgemdir=$(ruby -e 'print Gem.default_dir')
	export GEM_HOME="$gemhome"
	export GEM_PATH="$gemhome:$sysgemdir"

	cd "$SRC"

	gem install --local --ignore-dependencies \
		--bindir "$PKGDEST/usr/bin" \
		"asciidoctor-${pkgver}.gem"
	install -D -m644 man/asciidoctor.1 \
		"$PKGDEST/usr/share/man/man1/asciidoctor.1"

	test -x "$PKGDEST/usr/bin/asciidoctor"
	test -d "$gemhome/gems/asciidoctor-${pkgver}/lib"
	test -f "$PKGDEST/usr/share/man/man1/asciidoctor.1"

	# End-to-end through the shipped entrypoint: the wrapper's
	# #!/usr/bin/ruby resolves to the build-root ruby, GEM_HOME
	# points it at the staged gem, and a minimal document must
	# convert (this is the exact operation cryptsetup doc builds
	# will rely on).
	printf '= Smoke\n\nHi.\n' > "$BUILDDIR/smoke.adoc"
	"$PKGDEST/usr/bin/asciidoctor" -o "$BUILDDIR/smoke.html" \
		"$BUILDDIR/smoke.adoc"
	test -s "$BUILDDIR/smoke.html"
}

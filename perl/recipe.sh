#!/bin/sh

pkgname=perl
pkgver=5.42.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Practical Extraction and Report Language (system perl; modules install under /usr/lib/perl5)'
license='Artistic-1.0-Perl OR GPL-1.0-or-later'
origin=perl
repo=saphira
url=https://www.perl.org/

# Vendored official CPAN source tarball, byte-pinned. Configuration
# mirrors the proven generation-zero Stage4 perl exactly (verified via
# `perl -V` on Egg): no threads, static libperl, same /usr/lib/perl5
# @INC layout - so packaged modules overlay the same namespace.
# x86-64-v3 comes from the Saphira gcc toolchain defaults (--with-arch).
perl_sha256='73cf6cc1ea2b2b1c110a18c14bbbc73a362073003893ffcedc26d22ebdbdd0c3'

depends=""
makedepends="
	gcc
	make
"

recipe_build()
{
	echo "$perl_sha256  $RECIPE_DIR/files/perl-${pkgver}.tar.xz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/perl-${pkgver}.tar.xz"
	cd "$SRC"
	./Configure -des \
		-Dcc=cc \
		-Dprefix=/usr \
		-Dscriptdir=/usr/bin \
		-Dman1dir=/usr/share/man/man1 \
		-Dman3dir=/usr/share/man/man3 \
		-Duselargefiles \
		-Doptimize='-O2' \
		-Dccflags='-D_GNU_SOURCE -fwrapv -fno-strict-aliasing -pipe -fstack-protector-strong -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -D_FORTIFY_SOURCE=2'
	make -j${JOBS:-$(nproc)}

	# System-perl validation: interpreter identity, core functionality,
	# pod tooling needed by scripted packages. -Ilib: pre-install, the
	# build tree's lib/ carries Config.pm and the core modules.
	./perl -Ilib -V
	./perl -Ilib -e 'print "perl-ok\n"' | grep -q perl-ok
	./perl -Ilib -MConfig -e 'exit 1 unless $Config{prefix} eq "/usr"'
	./perl -Ilib -Mstrict -Mwarnings -e 'exit((1+1==2) ? 0 : 1)'
	./perl -Ilib -e 'require POSIX; require Socket; print "core-ok\n"' | grep -q core-ok
	# pod2man is built by the podlators core dist (promoted to /usr/bin
	# by `make install`, asserted in recipe_install); validate the pod
	# toolchain via its modules.
	./perl -Ilib -MPod::Man -MPod::Simple -e 'print "pod-ok\n"' | grep -q pod-ok
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# The bootstrap perl is replaced by this package on real systems;
	# keep installed paths identical (/usr/bin/perl, /usr/lib/perl5/...).
	find "$PKGDEST" -name perllocal.pod -delete
	# pod2man is required by scripted packages (MakeMaker man pages,
	# resource-agents ldirectord.8): assert it reached /usr/bin.
	test -x "$PKGDEST/usr/bin/pod2man"
}

#!/bin/sh

pkgname=rabbitmq-server
pkgver=4.3.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="RabbitMQ message broker (OpenStack messaging transport)"
license='MPL-2.0'
origin=rabbitmq-server
repo=saphira
url=https://www.rabbitmq.com/
source=https://github.com/rabbitmq/rabbitmq-server/releases/download/v4.3.6/rabbitmq-server-4.3.6.tar.xz
sha256=ea702e5fb89ac0c8822fac820cf60bb354c8af4149337dad863f9f08072ee612

depends="
    erlang
    elixir
    python3
"

makedepends="
    binutils
    gcc
    make
    python3
    rsync
    unzip
    zip
    erlang
    elixir
"

# The 4.3.6 release tarball vendors all 52 Erlang deps (deps/);
# ELIXIR=system uses the native elixir package for the CLI tools.
# GNU Make build (no Bazel); man pages are a separate target and are
# not built (would need the xmlto toolchain).
# erlang.mk builds in-source (same OTP family constraint as erlang
# itself), so build on a copy, keeping the vendored extraction
# pristine. The escript-zip step defaults to 7z (unavailable: no
# 7-Zip in the headless universe); ESCRIPT_ZIP is a make-overridable
# knob and Info-ZIP creates the identical appended zip payload.
recipe_build()
{
	cp -r "$SRC/." "$BUILDDIR/" && cd "$BUILDDIR"
	ESCRIPT_ZIP="zip -9 -X -q" make
}

recipe_install()
{
	# Plain `install` stops at install-erlapp + install-scripts
	# (sbin/ under the app dir); the bin/ symlinks operators and
	# units invoke come from install-bin. Man pages stay skipped
	# (their build needs the xmlto toolchain).
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" PREFIX=/usr \
		RMQ_ROOTDIR=/usr/lib/rabbitmq install install-bin
	install -D -m 0755 "$RECIPE_DIR/files/rabbitmq-server.initd" \
		"$PKGDEST/etc/init.d/rabbitmq-server"
	install -D -m 0644 "$RECIPE_DIR/files/rabbitmq-server.confd" \
		"$PKGDEST/etc/conf.d/rabbitmq-server"
	install -D -m 0644 "$RECIPE_DIR/files/rabbitmq-server.service" \
		"$PKGDEST/usr/lib/systemd/system/rabbitmq-server.service"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/rabbitmq" \
		"$PKGDEST/usr/share/saphira/accounts.d/rabbitmq-server"
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/rabbitmq" \
		"$PKGDEST/usr/share/saphira/fhs.d/rabbitmq-server"
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/rabbitmq-server" \
		"$PKGDEST/etc/logrotate.d/rabbitmq-server"
	install -D -m 0644 "$RECIPE_DIR/files/rabbitmq-server.tmpfiles" \
		"$PKGDEST/usr/lib/tmpfiles.d/rabbitmq-server.conf"
	for p in \
		usr/lib/rabbitmq/bin/rabbitmq-server \
		usr/lib/rabbitmq/bin/rabbitmqctl \
		etc/init.d/rabbitmq-server \
		usr/lib/systemd/system/rabbitmq-server.service \
		usr/share/saphira/accounts.d/rabbitmq-server \
		usr/share/saphira/fhs.d/rabbitmq-server \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: rabbitmq-server payload is missing $p" >&2
			return 1
		}
	done
}

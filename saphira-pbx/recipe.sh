#!/bin/sh
# saphira-pbx: management and control product for Asterisk on Saphira.
# Single control engine with a scriptable CLI, a fullscreen C TUI and
# the bearer-auth MCP network transport (`mcp serve`). SQLite holds
# the desired state; Asterisk configuration under
# /etc/asterisk/saphira/ is rendered output.
#
# AKADATA-owned code, BUSL-1.1 (see LICENCE-summary in the project
# repo; the packaging copy installs below). This licence applies to
# this package only: the asterisk recipe packages upstream Asterisk
# under GPL-2.0-only (with its documented exceptions) and pjproject
# under GPL-2.0-or-later; no licence inference crosses that boundary.
# Builds from the v0.2.0 tag tarball of the saphira-pbx project repo
# (see files/PROVENANCE.md).

pkgname=saphira-pbx
pkgver=0.2.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira PBX management and control for Asterisk"
license="BUSL-1.1"
origin=saphira-pbx
repo=saphira
url=https://github.com/SaphiraLinux/saphira-pbx
source=https://github.com/SaphiraLinux/saphira-pbx/archive/refs/tags/v0.2.0.tar.gz
sha256=46aa03bcf0f39114430082e5449eed571c59a43509f7ef29444a496d9a6c8790

# Hard dependency, deliberately: this is the control layer for the
# Saphira Asterisk PBX, not a standalone inspection tool. Installing
# saphira-pbx brings in the engine it manages. No asterisk-dev in
# makedepends: the C does not link Asterisk libraries; runtime control
# goes through argv-executed `asterisk -rx` on the local socket.
# sqlite (the shell, not just -dev) is a build dependency because
# `make test` drives the CLI harness through sqlite3 assertions.
# tar and diffutils are runtime dependencies: backup/restore shells
# tar, and the diff command shells diff(1) (both argv-executed, never
# a shell). Saphira is non-usrmerged: absolute tool paths are never
# assumed, hence PATH lookup.
# sqlite and openssl are DIRECT runtime links (-lsqlite3 -lcrypto);
# jansson and ncurses are DIRECT runtime links since v0.2.0
# (-ljansson for the serve transport, -lncurses for the TUI).
# All four are declared even where asterisk pulls some transitively:
# if the engine's dependency ever narrows, this package must not
# break silently. curl and python3 are test-harness needs (`make
# test` drives the live transport over curl and raw sockets via
# python3); the build seed carries both, and they are declared so
# the harness never depends on seed accidents.
depends="
    asterisk
    diffutils
    jansson
    ncurses
    openssl
    sqlite
    tar
"

makedepends="
    binutils
    curl
    gcc
    jansson-dev
    make
    ncurses-dev
    openssl-dev
    python3
    sqlite
    sqlite-dev
"

subpackages="saphira-pbx-doc"

recipe_build()
{
	# The worker flattens a single top-level archive dir into $SRC,
	# so the tree root lands directly in $SRC.
	cd "$SRC"
	make
	# The CLI harness runs here, in the build: a binary that fails
	# its own tests must not become a package. Tests run unprivileged
	# against scratch state (PBX_ALLOW_NONROOT); the installed paths
	# stay root-only at runtime.
	make test
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	[ -x "$PKGDEST/usr/sbin/saphira-pbx" ] || \
		{ echo "ERROR: saphira-pbx payload is missing the binary" >&2; return 1; }
	[ -e "$PKGDEST/usr/share/man/man8/saphira-pbx.8" ] || \
		{ echo "ERROR: saphira-pbx payload is missing the man page" >&2; return 1; }
	# The v0.2.0 binary must be the transport build: refuse a stale
	# stub payload before it can ship behind service units that
	# invoke the real `mcp serve` interface. `--help` exits 2 by
	# design, so capture-then-match (never a pipefail-sensitive
	# pipeline), and show output on mismatch for the build log.
	help_out=$("$PKGDEST/usr/sbin/saphira-pbx" --help 2>&1 || true)
	case $help_out in
	*"mcp serve"*) ;;
	*) echo "ERROR: payload lacks the v0.2.0 transport interface" >&2;
		printf '%s\n' "$help_out" | head -8 >&2; return 1 ;;
	esac
	# Shipped licence text (packaging derivative of the canonical
	# LICENCE-summary.txt in the project repo) and provenance record.
	install -D -m 0644 "$RECIPE_DIR/files/LICENCE-summary.txt" \
		"$PKGDEST/usr/share/licenses/saphira-pbx/LICENSE.txt"
	install -D -m 0644 "$RECIPE_DIR/files/PROVENANCE.md" \
		"$PKGDEST/usr/share/doc/saphira-pbx/PROVENANCE.md"
	# Transport config default: loopback-only plain HTTP. Operators
	# enabling TLS edit this file (see saphira-pbx(8)); the packaged
	# default never exposes the API beyond localhost by itself.
	install -D -m 0644 "$RECIPE_DIR/files/mcp.conf" \
		"$PKGDEST/etc/saphira-pbx/mcp.conf"
	# Dual init: both formats ship unconditionally, neither is enabled
	# at install time (enabling is a profile decision, never automatic).
	# Both invoke the real v0.2.0 `mcp serve` interface above; the
	# daemon runs as root by design and drops its network half to
	# saphira-pbx-mcp itself (see the unit comments).
	install -D -m 0644 "$RECIPE_DIR/files/saphira-pbx-mcp.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-pbx-mcp.service"
	install -D -m 0755 "$RECIPE_DIR/files/saphira-pbx-mcp.initd" \
		"$PKGDEST/etc/init.d/saphira-pbx-mcp"
	# Service identity: saphira-pbx-mcp, fixed UID/GID 155. State and
	# TLS directory map declared here; the reconciler creates them at
	# install time (never useradd in services).
	# Fragment name matches the owning output (makepkg refuses
	# foreign fragments); the declared identity inside stays
	# saphira-pbx-mcp.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-pbx" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-pbx"
}

#!/bin/sh

pkgname=saphira-agents
pkgver=1.0
# r2: payload change (multi-backend installer: npm + vendor-direct
# with hash verification + pip machinery; ten musl-proven agents in
# the catalogue, failures hidden per policy). r1 was published.
pkgrel=2
# x86_64, not noarch: apk-tools v3 fetches noarch payloads from a
# per-arch noarch/ subdir that the Saphira repo layout does not
# publish yet (verified 2026-09-08: hatched/noarch/ absent, fetch
# ENOENT). Revisit noarch if that layout lands; the closure is
# arch-specific anyway.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Coding-agent workstation: installer command plus tooling dependencies'
# Our own product, so our licence (BUSL-1.1, saphira-base pattern).
# Members and later npm selections keep their upstream licences.
license='BUSL-1.1'
origin=saphira-agents
repo=saphira
url=https://saphira.vm2.uk/
# Local original: developed in the private saphira-agents repository;
# files/ below carries the exact bytes (dev commit 05613d0). The
# isolated build root has no host /home access, so the bytes must
# travel with the recipe, never by path reference.

# Bare package names on purpose (never pinned versions): apk add
# installs the newest versions currently published in the configured
# Saphira repository and apk upgrade keeps them current. "Latest"
# means latest packaged and signed by Saphira, never a runtime
# download. Coding agents and provider SDKs are NOT members: that
# ecosystem moves too fast for APK rebuilds and is owned explicitly
# by the installer at operator request (per-user default, global
# under sudo). No separate `npm` member is needed: the nodejs
# package already ships the /usr/bin/npm and /usr/bin/npx
# launchers, which the installer drives.
#
# Node.js invariant: the runtime is the Saphira nodejs APK only
# (bare `nodejs` dep above; nodejs22 is never pulled in
# automatically). The installer consumes /usr/bin/node and
# /usr/bin/npm owned by that APK and installs npm application
# packages only -- never the Node/npm runtime itself.
#
# Backend runtimes, listed exactly as consumed (nothing else):
# curl + ca-certificates fetch vendor artefacts over TLS; tar
# extracts them. The pip backend needs python3/python3-pip only
# when a pip row ships -- none does, so they stay out.
depends="
    bubblewrap
    ca-certificates
    curl
    grit
    nodejs
    rtk
    tar
"

# Single C11 source, no configure: compiled directly like getent.
makedepends="
    gcc
"

recipe_build()
{
	# getent idiom: honour the builder CFLAGS, static musl binary,
	# warnings are errors (the crate gate for C).
	gcc ${CFLAGS-} -std=c11 -Wall -Wextra -Werror -static -Os -s \
		-o saphira-agents "$RECIPE_DIR/files/saphira-agents.c"
}

recipe_install()
{
	install -D -m 0755 saphira-agents \
		"$PKGDEST/usr/bin/saphira-agents"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-agents.8" \
		"$PKGDEST/usr/share/man/man8/saphira-agents.8"
	install -D -m 0644 "$RECIPE_DIR/files/README.group" \
		"$PKGDEST/usr/share/doc/saphira-agents/README.group"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-agents/LICENSE"
	# Root-owned global state directory (payload-owned; per-user
	# state lives under ~/.local/share and is never packaged).
	install -d -m 0755 "$PKGDEST/var/lib/saphira-agents"
	# Smoke checks: all read-only (no installs, no state writes,
	# no HOME writes). --list exercises the table; --installed
	# exercises both state paths while absent.
	./saphira-agents --help
	./saphira-agents --list > /dev/null
	HOME="$BUILDDIR/no-home" ./saphira-agents --installed
}

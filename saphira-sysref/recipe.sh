#!/bin/sh
# Saphira recipe: saphira-sysref
#
# Minimal local man-page context for AI agents (MCP/CLI sysref tool),
# extended with generic C header symbol resolution and local API docs.
#
# Built from the private in-house github remote rather than a vendored
# tarball, so the packaged bytes are the reviewed repository at a pinned
# revision. The revision is the origin/Master tip at packaging time and is
# recorded in the package, so a rebuild of the same pkgver is the same source.
# The repository stays private until decided otherwise; the recipe field
# states the package terms (BUSL-1.1, as published).

pkgname=saphira-sysref
pkgver=0.1.0
pkgrel=13
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Minimal local man-page context for AI agents (MCP/CLI sysref tool)'
license='BUSL-1.1'
origin=saphira-sysref
repo=saphira
url=https://saphira.vm2.uk/
# Built from the in-house github remote rather than a vendored tarball, so
# the packaged bytes are the reviewed repository at a pinned revision. The
# revision is the origin/Master tip at packaging time and is recorded in
# the package, so a rebuild of the same pkgver is the same source.
# Anonymous HTTPS: the builder worker carries no SSH identity by design
# (root is never used), so the remote must stay reachable without
# credentials; a private remote fails closed here. Treat it as a public
# repo: transport is read-only clone plus detached pin, nothing else.
saphira_sysref_url=https://github.com/SaphiraLinux/saphira-systef.git
saphira_sysref_branch=Master
saphira_sysref_rev=af2b3eb8f72154a566c8965a5afc97a6fe42a978

depends=""
# git is a build dep, not decoration: the remote is cloned at build time
# (see recipe_build). Everything else is the native musl compile closure.
makedepends="
	gcc
	git
	make
"
subpackages="$pkgname-doc"

recipe_build()
{
	# Anonymous HTTPS only: the isolated worker has no SSH identity and
	# must never depend on one. If the remote stops being publicly
	# reachable this fails closed naming the URL, never silently.
	if ! git clone --branch "$saphira_sysref_branch" "$saphira_sysref_url" sysref >>"$BUILDDIR/clone.log" 2>&1; then
		echo "ERROR: cannot reach the saphira-sysref remote ($saphira_sysref_url)" >&2
		tail -20 "$BUILDDIR/clone.log" >&2 || true
		return 1
	fi
	cd sysref
	# The clone above is transport only; the pin decides what gets built,
	# and the resolved commit is recorded into the package so an
	# installed copy can be traced back to exact source.
	git fetch --tags origin 2>/dev/null || true
	git checkout --detach "$saphira_sysref_rev"
	git rev-parse HEAD > "$BUILDDIR/saphira-sysref.rev"
	echo "building saphira-sysref $(cat "$BUILDDIR/saphira-sysref.rev")"
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=-march=x86-64-v3 ;;
		aarch64) march=-march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-sysref: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -j${JOBS:-$(nproc)} CC=gcc CFLAGS="-std=gnu11 -Os -Wall -Wextra $march" STATIC=0
	# Single self-check run (validation budget: the package runs its
	# proof once at build time; heavier bench/stress modes are manual).
	# No pipe: grep -q quitting early SIGPIPEs the writer under
	# pipefail and fails the build spuriously. The tool has no --help
	# flag (it prints usage with a nonzero exit), so ignore its status
	# and assert on the captured output instead.
	./sysref --help >"$BUILDDIR/help.txt" 2>&1 || true
	grep -q 'sysref QUERY' "$BUILDDIR/help.txt"
}

recipe_install()
{
	cd "$SRC/sysref"
	install -D -m 0755 sysref "$PKGDEST/usr/bin/sysref"
	install -D -m 0644 docs/sysref.1 "$PKGDEST/usr/share/man/man1/sysref.1"
	# Empty 0600 config skeleton (APIKEY for webMCP goes here).
	install -D -m 0600 /dev/null "$PKGDEST/etc/sysref/sysref.conf"
	install -d "$PKGDEST/usr/share/saphira-sysref"
	install -m 0644 "$BUILDDIR/saphira-sysref.rev" \
		"$PKGDEST/usr/share/saphira-sysref/revision"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-sysref/LICENSE"
}

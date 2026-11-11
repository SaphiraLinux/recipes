#!/bin/sh
# Saphira recipe: saphira-memoryd
#
# SHAMPOO discovery server set (sqlite + mariadb backends), musl toolchain.
# No daemon is shipped: the package is the CLI set plus its man pages.
#
# Built from the in-house keeper git remote rather than a vendored tarball,
# so the packaged bytes are the reviewed repository at a pinned revision.
# The revision is the origin/Master tip at packaging time and is recorded
# in the package, so a rebuild of the same pkgver is the same source.

pkgname=saphira-memoryd
pkgver=0.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira Memory daemon (SHAMPOO discovery)"
# The recipe field states the package terms (BUSL-1.1, as published;
# see files/LICENSE for the WinRAR-style use grant: the software is
# free, commercial use requires a purchased licence, no liability,
# own risk). The build source itself stays private until the
# repository is opened publicly; source is available on request.
license="BUSL-1.1"
origin=saphira-memoryd
repo=saphira
url=https://saphira.vm2.uk/

# In-house remote. saphira_memoryd_rev pins an immutable ref -- the Master
# tip at packaging time -- so "the same pkgver" always means the same
# source. Never point it at a moving branch: a package recipe that builds
# whatever Master happens to be is not reproducible.
#
# The canonical origin is the keeper: remote below. "keeper:/path" is git's
# scp-like syntax, so it resolves only where an SSH host named 'keeper'
# exists. On a build host without that host entry, the equivalent local
# path is tried, and the error says which forms were tried rather than
# just "clone failed".
saphira_memoryd_url=keeper:/saphira-git-repo/saphira-memory.git
saphira_memoryd_branch=Master
saphira_memoryd_rev=f15226e05909a5e3fc9cecf77c505e45c557eb31
saphira_memoryd_local=/saphira-git-repo/saphira-memory.git

# Runtime closure: json-c, mariadb client, openssl (libcrypto), sqlite.
# No background service is installed or started.
depends="
    json-c
    mariadb
    openssl
    sqlite
"
# git + openssh are build deps, not decoration: the in-house remote is
# cloned at build time (see recipe_build). Everything else is the
# native musl compile closure plus the pkg-config probes the Makefile
# uses (json-c, sqlite3, libcrypto).
makedepends="
    binutils
    gcc
    git
    make
    openssh
    json-c-dev
    mariadb-dev
    openssl-dev
    pkgconf
    sqlite-dev
"
subpackages="$pkgname-doc"

# No Unix identity: the package ships CLI binaries and man pages
# only. No daemon is installed or enabled, no service user exists.
# No configuration payload: the estate config is user-owned state,
# never a system file.
# No logrotate fragment: nothing installed here writes log files.
# Dual-init exempt: no long-running service is shipped.

recipe_build()
{
	# Both remotes must yield the same commit; they are the same repository
	# reached two ways. Whichever answers first is checked out at the pin,
	# so a stale mirror cannot quietly package different source.
	#
	# BatchMode fails closed on missing credentials instead of hanging
	# on a password prompt; accept-new trusts the host key on first
	# contact inside the ephemeral worker and verifies afterwards.
	export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"
	cloned=no
	for url in "$saphira_memoryd_url" "$saphira_memoryd_local"; do
		if git clone --branch "$saphira_memoryd_branch" "$url" saphira-memory \
				>>"$BUILDDIR/clone.log" 2>&1; then
			cloned=yes
			echo "cloned $url"
			break
		fi
		echo "  not reachable: $url" >>"$BUILDDIR/clone.log"
	done
	if [ "$cloned" = no ]; then
		echo "ERROR: cannot reach the saphira-memory remote; tried:" >&2
		grep 'not reachable' "$BUILDDIR/clone.log" >&2 || true
		return 1
	fi
	cd saphira-memory
	# The clone above is transport only; the pin decides what gets built,
	# and the resolved commit is recorded into the package so an
	# installed copy can be traced back to exact source.
	git fetch --tags origin 2>/dev/null || true
	git checkout --detach "$saphira_memoryd_rev"
	git rev-parse HEAD > "$BUILDDIR/saphira-memoryd.rev"
	echo "building saphira-memoryd $(cat "$BUILDDIR/saphira-memoryd.rev")"

	# Saphira musl toolchain is the supported build path.
	make -j"${JOBS:-$(nproc)}" CC=gcc all

	# The gates run at package-build time. musl-check is the package's
	# conservative-subset contract (no glibc-only symbols in our
	# objects); a package that cannot prove it does not get installed.
	make musl-check > "$BUILDDIR/musl-check.log" 2>&1 || {
		echo "ERROR: musl-check failed; see $BUILDDIR/musl-check.log" >&2
		tail -20 "$BUILDDIR/musl-check.log" >&2
		return 1
	}
	# Smoke test: every shipped binary executes and reports its version.
	for b in saphira-memoryd saphira-memory-spoke \
	         saphira-memoryd-tasks saphira-memory-pump saphira-shampoo \
	         saphira-qrmem saphira-memoryctl; do
		[ -x "$b" ] || { echo "ERROR: $b missing after make" >&2; return 1; }
		"./$b" --version >/dev/null || return 1
	done
	echo "gates: musl-check ok, 7 binaries smoke-tested"
}

recipe_install()
{
	cd "$SRC/saphira-memory"

	# Explicit file lists only. In particular the source tree's
	# android/ directory is NEVER packaged: this recipe ships the
	# SHAMPOO CLI set and its man pages, nothing else.
	install -d "$PKGDEST/usr/bin"
	for b in saphira-memoryd saphira-memory-spoke \
	         saphira-memoryd-tasks saphira-memory-pump saphira-shampoo \
	         saphira-qrmem saphira-memoryctl; do
		install -m 0755 "$b" "$PKGDEST/usr/bin/$b"
	done

	install -d "$PKGDEST/usr/share/man/man1"
	for m in man/man1/*.1; do
		install -m 0644 "$m" "$PKGDEST/usr/share/man/man1/${m##*/}"
	done
	install -d "$PKGDEST/usr/share/man/man7"
	for m in man/man7/*.7; do
		install -m 0644 "$m" "$PKGDEST/usr/share/man/man7/${m##*/}"
	done
	install -d "$PKGDEST/usr/share/man/man8"
	for m in man/man8/*.8; do
		install -m 0644 "$m" "$PKGDEST/usr/share/man/man8/${m##*/}"
	done

	install -d "$PKGDEST/usr/share/doc/saphira-memoryd"
	install -m 0644 "$BUILDDIR/saphira-memoryd.rev" \
		"$PKGDEST/usr/share/saphira-memoryd/revision"

	install -d "$PKGDEST/usr/share/licenses/saphira-memoryd"
	install -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-memoryd/LICENSE"

	# No post-install generation, no first-boot download, no model shipped.
	# A package that reached for the network at install time would be
	# unbuildable offline and unreviewable.
}

recipe_check()
{
	# Post-install: prove the installed binaries run and report versions.
	for b in saphira-memoryd saphira-memory-spoke \
	         saphira-memoryd-tasks saphira-memory-pump saphira-shampoo \
	         saphira-qrmem saphira-memoryctl; do
		"$PKGDEST/usr/bin/$b" --version || return 1
	done
	echo "check: installed binaries run"
	return 0
}

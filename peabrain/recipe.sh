#!/bin/sh

pkgname=peabrain
pkgver=1.0.1
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Persistent agent memory MCP server (SQLite-backed, stdio)'
license='BUSL-1.1'
origin=peabrain
repo=saphira
url=https://github.com/akadatalimited/PeaBrain
# No upstream tarball: vendored from the annotated v1.0.1 tag
# (Saphira packaging baseline) via git archive. The public repo
# stays the source of truth; this archive pins the exact bytes.
source=peabrain-1.0.1.tar.gz
sha256=c8ac5372148fe4d5d550c9d9d1837e1784bfec10ae8d9497d95dd7265e95ab4a

# Saphira-owned (AKADATA LIMITED): BUSL-1.1 with the Saphira Additional
# Use Grant; the upstream repo carries no license file yet, so none
# ships here - the grant lives in the collection's COMMERCIAL-LICENSING.md.
#
# Pure-FASM x86-64 MCP stdio server: no libc, no interpreter, raw
# syscalls only (static PIE, no INTERP), so there is nothing to link
# and depends stays empty. Requires x86-64-v3 at runtime (AVX/AVX2/
# FMA/BMI1/BMI2/LZCNT; the binary refuses cleanly on older CPUs).
#
# State lives wherever $PEABRAIN_STATE_DIR points. The Saphira
# integration target is /var/saphira/PeaBrain (owned peabrain:peabrain,
# 0700, declared in files/accounts.d/peabrain - the binary refuses any
# state dir that is not 0700 and owner-only): point the MCP client at
# it to share one store. Left unset, the XDG default applies.
# Binary installs lowercase /usr/bin/peabrain (upstream brands it
# PeaBrain), root-owned 0755, deliberately NOT setuid: a setuid
# transition blinds the process's own /proc/self/environ reads
# (verified on Egg), so the privilege boundary lives in the packaged
# sudoers fragment (files/sudoers.d/peabrain) and the transition is
# a full user switch (sudo -u peabrain), never a kernel bit.

depends=""
makedepends="
    fasm
"

subpackages="$pkgname-doc"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/peabrain-1.0.1.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/peabrain-1.0.1.tar.gz"
	# The sudoers fragment ships with the package, so it is
	# validated like any other payload: present, non-empty, and
	# newline-terminated (sudo fails closed on a malformed file,
	# and a missing trailing newline breaks its last line).
	[ -s "$RECIPE_DIR/files/sudoers.d/peabrain" ] || {
		echo "ERROR: sudoers fragment missing or empty" >&2
		return 1
	}
	[ -z "$(tail -c 1 "$RECIPE_DIR/files/sudoers.d/peabrain")" ] || {
		echo "ERROR: sudoers fragment lacks trailing newline" >&2
		return 1
	}

	# The committed PeaBrain binary must be byte-identical to what
	# the vendored fasm builds from the vendored source: the repo
	# claims reproducible builds, and this gate proves it on every
	# Saphira build instead of trusting the checked-in bytes.
	test -x "$SRC/PeaBrain" || {
		echo "ERROR: reference binary absent: $SRC/PeaBrain" >&2
		return 1
	}
	command -v cmp >/dev/null 2>&1 || {
		echo "ERROR: cmp is absent from the build root (identity proof would be vacuous)" >&2
		return 1
	}
	cd "$SRC" || return 1
	fasm -m 65536 peabrain.asm "$BUILDDIR/peabrain" || {
		echo "ERROR: fasm assembly failed" >&2
		return 1
	}
	test -x "$BUILDDIR/peabrain" || {
		echo "ERROR: fresh binary missing" >&2
		return 1
	}
	if ! cmp -s "$BUILDDIR/peabrain" "$SRC/PeaBrain"; then
		echo "ERROR: fresh binary differs from the committed reference build" >&2
		ls -l "$BUILDDIR/peabrain" "$SRC/PeaBrain" >&2
		return 1
	fi
	# Execution smoke test: the fresh binary runs to a clean exit
	# on empty stdin (the server flushes and exits 0 on EOF - see
	# the read loop). This proves the binary executes on this CPU
	# (the x86-64-v3 gate refuses older iron loudly instead of
	# faulting), the stdio path works, and shutdown persists
	# cleanly. Deliberately no MCP roundtrip here: protocol
	# correctness is proven upstream and on target hardware, while
	# output matching in the hermetic root proved too brittle to
	# own a build gate. Full write/read verification happens on
	# Minimer after install.
	smoke_dir=$(mktemp -d) || return 1
	chmod 0700 "$smoke_dir" || return 1
	if ! PEABRAIN_STATE_DIR=$smoke_dir \
		"$BUILDDIR/peabrain" </dev/null >"$BUILDDIR/smoke.out" 2>"$BUILDDIR/smoke.err"; then
		echo "ERROR: fresh binary failed to run to a clean exit" >&2
		echo "--- smoke.err ---" >&2
		cat "$BUILDDIR/smoke.err" >&2
		rm -rf -- "$smoke_dir"
		return 1
	fi
	rm -rf -- "$smoke_dir"
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/peabrain" "$PKGDEST/usr/bin/peabrain"
	# The binary is deliberately NOT setuid: a setuid transition
	# blinds the process's own /proc/self/environ reads (verified on
	# Egg - identical invocation works un-setuid, fails setuid), so
	# the privilege boundary lives in sudoers, never in the binary
	# bit. Assert the absence, so a future chmod cannot silently
	# reintroduce it.
	if test -u "$PKGDEST/usr/bin/peabrain"; then
		echo "ERROR: peabrain must not be setuid (see above)" >&2
		return 1
	fi
	# Service identity declaration (peabrain:181, state dir only);
	# makepkg reconciles it on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/peabrain" \
		"$PKGDEST/usr/share/saphira/accounts.d/peabrain"
	# Sudoers privilege boundary (0440, owned by the package).
	install -D -m 0440 "$RECIPE_DIR/files/sudoers.d/peabrain" \
		"$PKGDEST/etc/sudoers.d/peabrain"
	install -D -m 0644 "$SRC/README.md" \
		"$PKGDEST/usr/share/doc/$pkgname/README.md"
	install -D -m 0644 "$SRC/BUILD" \
		"$PKGDEST/usr/share/doc/$pkgname/BUILD"
	test -x "$PKGDEST/usr/bin/peabrain" || {
		echo "ERROR: packaged peabrain missing: $PKGDEST/usr/bin/peabrain" >&2
		return 1
	}
}

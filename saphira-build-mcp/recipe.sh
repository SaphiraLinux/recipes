#!/bin/sh

pkgname=saphira-build-mcp
pkgver=0.10.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Read-only Saphira build/package queries for AI agents (local MCP stdio server, tools.conf extensions)'
license='BUSL-1.1'
origin=saphira-build-mcp
repo=saphira
url=https://github.com/SaphiraLinux/saphira-build-mcp
# Pinned release bytes, vendored under files/ (verified, never
# re-downloaded at build time; the public mirror stays pure-text and
# public builders fetch via this URL):
vendor=https://github.com/SaphiraLinux/saphira-build-mcp/releases/download/v0.10.9/saphira-build-mcp-0.10.9.tar.xz
sha256=adf3b91aff61602d1867347a3af925b22b4151b5353bab4e924cad8d49732ccf

depends="
	sqlite
"
makedepends="
	gcc
	make
	sqlite-dev
"
subpackages="$pkgname-doc"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE.
	MCBALL="$RECIPE_DIR/files/saphira-build-mcp-0.10.9.tar.xz"
	if [ -f "$MCBALL" ]; then
		echo "$sha256  $MCBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local saphira-build-mcp-0.10.9.tar.xz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		MCBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$MCBALL"
	cd "$SRC"
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=-march=x86-64-v3 ;;
		aarch64) march=-march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-build-mcp: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -j${JOBS:-$(nproc)} CC=gcc CFLAGS="-std=gnu11 -Os -Wall -Wextra $march" STATIC=0
	# Bounded protocol self-check (validation budget: list-tools plus
	# one initialize/ping round trip; the full hermetic suite runs in
	# source development where sqlite3 fixture tooling is present).
	# It must not depend on live production databases being mounted
	# into the build namespace.
	./saphira-build-mcp --list-tools >"$BUILDDIR/tools.json"
	grep -q '"name":"package_why_installed"' "$BUILDDIR/tools.json"
	for tool in package_search package_info package_dependencies \
		package_why_installed package_installed package_build_status \
		package_build_history package_build_log package_artifacts \
		build_queue package_identity package_notes_get \
		package_notes_add package_policy_status package_policy_record \
		package_readiness build_request package_bump \
		checkpoint_save checkpoint_resume checkpoint_list \
		checkpoint_close total_recall; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools.json" \
			|| { echo "ERROR: tool $tool missing from tools/list" >&2; return 1; }
	done
	# No shell anywhere on the extension path: execve/fork only.
	if grep -rn --include='*.c' -E '(^|[^_a-zA-Z])system[[:space:]]*\(|popen[[:space:]]*\(' src/; then
		echo "ERROR: shell escape in extension runner" >&2; return 1
	fi
	# The shipped example conf must parse: its narrow tools appear,
	# checkpoint_* stay unconditional, and nothing else leaks in.
	SBM_TOOLS_CONF="$SRC/tools.conf.example" \
		./saphira-build-mcp --list-tools >"$BUILDDIR/tools-ext.json"
	for tool in repo_status repo_diffcheck repo_diffstat recipe_verify; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools-ext.json" \
			|| { echo "ERROR: example tool $tool missing from tools/list" >&2; return 1; }
	done
	grep -q '"name":"checkpoint_list"' "$BUILDDIR/tools-ext.json" \
		|| { echo "ERROR: checkpoint register must stay exposed" >&2; return 1; }
	# Portable mode (SBM_SAPHIRA=off): the journal capability stays
	# listed (checkpoints, notes, policy tools, readiness,
	# total_recall), Saphira-state tools are gone, build tools stay
	# (separate capability, on by default), and an invalid value
	# fails outright. List-only here needs no journal database.
	SBM_SAPHIRA=off SBM_TOOLS_CONF=/nonexistent-tools.conf \
		./saphira-build-mcp --list-tools >"$BUILDDIR/tools-portable.json"
	for tool in checkpoint_save checkpoint_resume checkpoint_list \
		checkpoint_close package_notes_get package_notes_add \
		total_recall package_policy_status package_policy_record \
		package_readiness; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools-portable.json" \
			|| { echo "ERROR: portable tool $tool missing from tools/list" >&2; return 1; }
	done
	for tool in package_search package_info package_dependencies \
		package_why_installed package_installed package_build_status \
		package_build_history package_build_log package_artifacts \
		build_queue package_identity; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools-portable.json" \
			&& { echo "ERROR: saphira tool $tool leaks into portable tools/list" >&2; return 1; }
	done
	for tool in build_request package_bump; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools-portable.json" \
			|| { echo "ERROR: build tool $tool wrongly gated by saphira mode" >&2; return 1; }
	done
	SBM_SAPHIRA=bogus ./saphira-build-mcp --list-tools \
		>"$BUILDDIR/tools-bogus.json" 2>/dev/null \
		&& { echo "ERROR: invalid SBM_SAPHIRA accepted" >&2; return 1; }
	# Build capability (SBM_BUILD=off): only the two privileged
	# mutations vanish; the journal set stays complete.
	SBM_BUILD=off SBM_TOOLS_CONF=/nonexistent-tools.conf \
		./saphira-build-mcp --list-tools >"$BUILDDIR/tools-nobuild.json"
	for tool in checkpoint_save package_notes_add package_policy_record \
		package_readiness total_recall package_info; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools-nobuild.json" \
			|| { echo "ERROR: journal tool $tool missing with build off" >&2; return 1; }
	done
	for tool in build_request package_bump; do
		grep -q "\"name\":\"$tool\"" "$BUILDDIR/tools-nobuild.json" \
			&& { echo "ERROR: build tool $tool leaks with build off" >&2; return 1; }
	done
	SBM_BUILD=bogus ./saphira-build-mcp --list-tools \
		>"$BUILDDIR/tools-bogus-build.json" 2>/dev/null \
		&& { echo "ERROR: invalid SBM_BUILD accepted" >&2; return 1; }
	# Help contract: --help/-h identical on stdout exit 0 with the
	# product attribution, --version names the release, unknown flags
	# stay usage-on-stderr exit 2, and no flag opens a database.
	./saphira-build-mcp --help >"$BUILDDIR/help.txt" 2>/dev/null \
		|| { echo "ERROR: --help failed" >&2; return 1; }
	./saphira-build-mcp -h >"$BUILDDIR/help-h.txt" 2>/dev/null \
		|| { echo "ERROR: -h failed" >&2; return 1; }
	cmp -s "$BUILDDIR/help.txt" "$BUILDDIR/help-h.txt" \
		|| { echo "ERROR: -h differs from --help" >&2; return 1; }
	for line in "saphira-build-mcp 0.10.9" "https://saphira.vm2.uk" \
		"https://www.akadata.co.uk" "https://shampoo.op2.uk" \
		"Shared Human-Agent-Model Platform for Orchestration"; do
		grep -q "$line" "$BUILDDIR/help.txt" \
			|| { echo "ERROR: --help missing: $line" >&2; return 1; }
	done
	./saphira-build-mcp --version >"$BUILDDIR/version.txt" 2>/dev/null \
		|| { echo "ERROR: --version failed" >&2; return 1; }
	grep -q "^saphira-build-mcp 0.10.9\$" "$BUILDDIR/version.txt" \
		|| { echo "ERROR: --version wrong" >&2; return 1; }
	./saphira-build-mcp --frobnicate >/dev/null 2>&1 \
		&& { echo "ERROR: unknown flag accepted" >&2; return 1; }
	SBM_SAPHIRA=bogus SBM_NOTES_DB=/nonexistent-xyz-notes.db \
		./saphira-build-mcp --help >/dev/null 2>&1 \
		|| { echo "ERROR: --help needs configuration" >&2; return 1; }
	printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' \
		'{"jsonrpc":"2.0","id":2,"method":"ping"}' \
		| ./saphira-build-mcp --mcp >"$BUILDDIR/ping.json" 2>/dev/null
	grep -q '"serverInfo":{"name":"saphira-build-mcp"' "$BUILDDIR/ping.json"
	grep -q '"result":{}' "$BUILDDIR/ping.json"
}

recipe_install()
{
	install -D -m 0755 "$SRC/saphira-build-mcp" "$PKGDEST/usr/bin/saphira-build-mcp"
	install -D -m 0644 "$SRC/saphira-build-mcp.1" "$PKGDEST/usr/share/man/man1/saphira-build-mcp.1"
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-build-mcp/LICENSE"
}

pkgname=saphira-unified-memory-mcp
pkgver=3.13.5
pkgrel=20
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='SQLite-backed MCP memory suite: unified stdio servers, optional remote bearer endpoint, debate runtime, MariaDB profile'
license='MIT'
replaces="akadata-unified-memory-mcp"
origin=saphira-unified-memory-mcp
repo=saphira
url=https://github.com/akadata/akadata-unified-memory-mcp

# r18: package renamed saphira-unified-memory-mcp (Genesis rebrand); payload,
# vendored source name, and /etc/akadata-memory config path stay unchanged:
# the config path is resolved inside the vendored python modules, and moving
# it would break deployed runtime configs on upgrade.
# Upstream is a PRIVATE github org repo; this build vendors a byte-pinned
# git snapshot (branch hotfix/remove-non-english-code @ e23fd76) produced by
# `git archive` on the build host, plus a pinned wheel bundle covering the
# pure-python runtime deps (fastmcp stack, PyMySQL) and the one binary wheel
# (pydantic-core, musllinux_1_1) for python 3.14 / x86_64.
akadata_unified_sha256=69cbd3a9ee3738c7a15bee4b0c89e3acbe5d9b6d76137ba7752415dda3131591
wheels_sha256=8d3a76aff5e30571ba0eb62f580e716d9fb704059b2dd1a1160a8a59f8429754

depends="python3 sqlite bash"
# Pure-python suite: no compilation. Only python3 is needed at build time
# (zipfile extraction); no compiler, make, or kernel UAPI consumption.
makedepends="python3"

recipe_build() {
	# Vendored contract: with no source= URL the worker stages the recipe
	# dir itself into $SRC (files/ subdir + recipe.sh, same contract as
	# netcat-openbsd/wireless-regdb). Verify byte identity first.
	echo "$akadata_unified_sha256  $SRC/files/akadata-unified-memory-mcp-3.13.5.tar.gz" | sha256sum -c -
	echo "$wheels_sha256  $SRC/files/wheels-vendor-20260901-r13.tar.gz" | sha256sum -c -
	# Nothing to compile: the suite ships as source modules + wheels.
	return 0
}

recipe_install() {
	local SP="$PKGDEST/usr/lib/python3.14/site-packages"
	mkdir -p "$SP" "$PKGDEST/usr/bin" "$PKGDEST/usr/share/doc/$pkgname"

	# -- vendored wheels -----------------------------------------
	tar --no-same-owner -C "$SRC" -xzf "$SRC/files/wheels-vendor-20260901-r13.tar.gz"
	# The vendored tarball carries its own SHA256SUMS listing the wheels.
	(cd "$SRC" && sha256sum -c SHA256SUMS)
	for w in "$SRC"/*.whl; do
		python3 -m zipfile -e "$w" "$SP/"
	done
	rm -f "$SP"/fastmcp_slim-* 2>/dev/null || true

	# -- the suite's own modules -----------------------------------------
	mkdir -p "$SRC/pkg"
	tar --no-same-owner -C "$SRC/pkg" --strip-components=1 \
		-xzf "$SRC/files/akadata-unified-memory-mcp-3.13.5.tar.gz"
	for f in "$SRC/pkg"/*.py; do
		cp "$f" "$SP/"
	done
	for d in hooks bin; do
		mkdir -p "$SP/$d"
		cp -r "$SRC/pkg/$d/." "$SP/$d/"
	done
	if [ -d "$SRC/pkg/tools" ]; then
		mkdir -p "$SP/tools"
		cp -r "$SRC/pkg/tools/." "$SP/tools/"
	fi

	# -- console scripts (canonical family; no gui on this profile) -------
	# Task tray needs PyQt6 (gui profile) and is intentionally not packaged
	# for Saphira; digest/reminders/debate-ops/doctor ship.
	local entry
	for entry in \
		"core=server:main" "mcp=server:main" "session=session_server:main" \
		"tasks=task_server:main" "bridge=bridge_server:main" \
		"collab=collab_server:main" "entity=entity_server:main" \
		"intel=intel_server:main" "unified=unified_server:main" \
		"doctor=install_doctor:main" "debate-ops=debate_ops:main" \
		"demo=demo_flow:main" "digest=daily_digest:main" \
		"reminders=reminder_scheduler:main" "n8n=n8n_server:main"; do
		local name=${entry%%=*} mod=${entry#*=}
		cat > "$PKGDEST/usr/bin/sqlite-memory-$name" <<EOF
#!/usr/bin/python
import sys
from ${mod%%:*} import ${mod#*:}
if __name__ == "__main__":
    sys.argv[0] = sys.argv[0].removesuffix(".exe")
    sys.exit(${mod#*:}())
EOF
		chmod 0755 "$PKGDEST/usr/bin/sqlite-memory-$name"
	done

	# -- config examples + docs + systemd unit ----------------------------
	mkdir -p "$PKGDEST/etc/akadata-memory" "$PKGDEST/usr/lib/systemd/user"
	install -m 0644 "$SRC/pkg/AKADATA_MCP.md" \
		"$PKGDEST/usr/share/doc/$pkgname/README.md"
	install -m 0644 "$SRC/pkg/LICENSE" "$PKGDEST/usr/share/doc/$pkgname/LICENSE"
	[ -f "$SRC/pkg/systemd/user/sqlite-memory-debate-pump.service" ] && \
		install -m 0644 "$SRC/pkg/systemd/user/sqlite-memory-debate-pump.service" \
			"$PKGDEST/usr/lib/systemd/user/"
	cat > "$PKGDEST/etc/akadata-memory/databases.toml.example" <<EOF
# sqlite-memory MCP database configuration (manual setup)
# Default profile below is the local SQLite store; edit the path.
default_profile = "local"

[profiles.local]
backend = "sqlite"
path = "/var/lib/sqlite-memory/memory.db"

# Optional shared/team backend - enable and set a mode-0600 password file.
# [profiles.team]
# backend = "mariadb"
# host = "127.0.0.1"
# port = 3306
# username = "memory"
# database = "memory"
# password_file = "/etc/akadata-memory/team.password"

# Optional remote unified endpoint (one authenticated MCP endpoint):
#   SQLITE_MEMORY_UNIFIED_HTTP=1
#   SQLITE_MEMORY_UNIFIED_HTTP_BEARER_FILE=/etc/akadata-memory/unified-http-bearer
#   (bearer file mode 0600; TLS expected in front when exposing beyond loopback)
EOF
}


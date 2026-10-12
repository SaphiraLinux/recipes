#!/bin/sh

# buildpkg static guards. Two things, both cheap and both about the
# orchestrator refusing to do damage:
#
#   - the build worker must refuse to run outside an isolated build root;
#   - every configuration key buildpkg reads through config[...] must
#     actually be one it loads.
#
# The second exists because that invariant was broken and nobody noticed for
# several weeks. The metadata sandbox probe read config["SAPHIRA_METADATA_SHELL"]
# while CONFIG_KEYS did not list it, so load_config() could never supply it and
# every build died with a bare KeyError naming the variable -- with no hint
# that the cause was a missing list entry rather than a missing environment
# variable. resolvepkg carried the key the whole time. A key read but never
# loaded fails at the first build and at no other time, which is the worst
# possible moment to discover it.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s BUILD-WORKER\n' "$0" >&2
	exit 1
}

worker=$1
if "$worker" example >/dev/null 2>&1; then
	printf '%s\n' 'buildpkg-single ran outside an isolated build root' >&2
	exit 1
fi
printf '%s\n' '  ok   buildpkg-single refuses to run outside an isolated build root'

buildpkg=$(dirname -- "$0")/../files/buildpkg
[ -f "$buildpkg" ] || {
	printf 'buildpkg-unprivileged: buildpkg is missing: %s\n' "$buildpkg" >&2
	exit 1
}

# Keys declared for load, and keys actually read through the config mapping.
# Each quoted name is extracted individually: CONFIG_KEYS is a multi-line
# tuple, so stripping punctuation would run neighbouring names together.
loaded=$(sed -n '/^CONFIG_KEYS = (/,/^)/p' "$buildpkg" |
	grep -oE '"SAPHIRA_[A-Z0-9_]+"' | tr -d '"' | sort -u)
[ -n "$loaded" ] || {
	printf 'buildpkg-unprivileged: no CONFIG_KEYS found in %s\n' "$buildpkg" >&2
	exit 1
}

read_keys=$(grep -oE 'config\["SAPHIRA_[A-Z0-9_]+"\]' "$buildpkg" |
	sed 's/config\["//; s/"\]//' | sort -u)

missing=
for key in $read_keys; do
	printf '%s\n' "$loaded" | grep -qx "$key" || missing="$missing $key"
done
if [ -n "$missing" ]; then
	printf 'buildpkg-unprivileged: buildpkg reads config keys it never loads:%s\n' \
		"$missing" >&2
	printf '%s\n' '  each must be added to CONFIG_KEYS, or load_config() cannot supply it' >&2
	exit 1
fi
printf '  ok   every config key buildpkg reads is one it loads (%s keys)\n' \
	"$(printf '%s\n' "$read_keys" | wc -l)"

printf '%s\n' 'buildpkg static guards: OK'

#!/bin/sh

# python-recipes.sh: static correctness gate for native python-* recipes in
# the OpenStack closure.
#
# Strictly checks the recipes listed in
# saphira-packager/files/openstack-python-closure.txt. Other python-*
# recipes predate this work and are counted as legacy/out-of-scope, never
# failed: this gate must not turn another agent's packages red.
#
# Proves, without building a package and without network access:
#   - every recipe parses
#   - every recipe installs OFFLINE: --no-index, --no-deps,
#     --no-build-isolation, --no-cache-dir
#   - every vendored archive matches its .sha256 sidecar
#   - the declared build backend is present in makedepends (with
#     --no-build-isolation a non-in-tree backend must be pre-installed, or
#     the build dies with BackendUnavailable). A backend-path (in-tree
#     backend, e.g. pbr self-hosting) needs only setuptools.
#   - no arch-specific payload (gcc/python3-dev native build deps) is
#     labelled pkgarch=noarch
#
# usage: python-recipes.sh [RECIPE_ROOT]

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
recipes=${1:-$root}
manifest=$root/saphira-packager/files/openstack-python-closure.txt

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch"
work=$(mktemp -d "$scratch/python-recipes.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

in_scope() {
	[ -f "$manifest" ] && grep -qx "$1" "$manifest"
}

# build-backend -> makedepends entry that provides it
backend_dep() {
	case "$1" in
	poetry.core.masonry.api) echo python-poetry-core ;;
	hatchling.build) echo python-hatchling ;;
	flit_core.buildapi) echo python-flit-core ;;
	mesonpy) echo python-meson-python ;; # installed backend, no backend-path in sdist
	scikit_build_core.build) echo python-scikit-build-core ;; # installed backend (pybind11)
	pbr.build) echo python-pbr ;;
	setuptools.build_meta | setuptools.build_meta:__legacy__ | '') echo setuptools ;;
	pep517_backend.hooks) echo '' ;; # in-tree backend-path backend
	*) echo "?$1" ;;
	esac
}

checked=0
legacy=0
for d in "$recipes"/python-*; do
	[ -f "$d/recipe.sh" ] || continue
	pkg=${d##*/}
	if ! in_scope "$pkg"; then
		legacy=$((legacy + 1))
		continue
	fi
	checked=$((checked + 1))

	sh -n "$d/recipe.sh" 2>/dev/null || { bad "$pkg: does not parse"; continue; }

	# Metadata assignments are sourced by the resolver/builder under
	# set -u inside a sandbox: a backtick or $() in a quoted value
	# executes at source time (python-platformdirs shipped e.g. a
	# `user data dir` pkgdesc, which broke every closure containing
	# it with `user: command not found`). Forbid command substitution
	# in the metadata header.
	if sed -n '1,40p' "$d/recipe.sh" | grep -qE '`|\$\('; then
		bad "$pkg: metadata contains command substitution (backtick or \$())"
	fi

	for flag in --no-index --no-deps --no-build-isolation --no-cache-dir; do
		grep -q -- "$flag" "$d/recipe.sh" || bad "$pkg: missing $flag"
	done

	arch=$(sed -n 's/^pkgarch=\(.*\)$/\1/p' "$d/recipe.sh")
	if [ "$arch" = noarch ] && grep -qE '^\s+(gcc|python3-dev)$' "$d/recipe.sh"; then
		bad "$pkg: pkgarch=noarch but declares native build deps"
	fi
	# An arch-specific package must assert its compiled artifact exists.
	# Several upstream projects (wcwidth, sqlalchemy, wrapt) treat their C
	# extension as optional and silently fall back to pure Python, which
	# publishes an arch NVR with no .so under the same identity. The
	# assertion turns that into a loud build failure.
	if [ "$arch" != noarch ] && ! grep -q 'staged payload is missing the compiled' "$d/recipe.sh"; then
		bad "$pkg: arch-specific but does not assert its compiled extension"
	fi

	# .zip sdists are legitimate upstream artefacts (e.g. simplegeneric
	# ships only a zip; docbook-xml already vendors one; the builder
	# extracts zips via unzip). They get the same treatment as wheels:
	# sidecar verification here, no pyproject backend probe below.
	sdist=$(ls "$d"/files/*.tar.gz "$d"/files/*.whl "$d"/files/*.zip 2>/dev/null | head -1)
	[ -n "$sdist" ] || { bad "$pkg: no vendored archive"; continue; }
	( cd "$d/files" && sha256sum -c "$(basename "$sdist").sha256" >/dev/null 2>&1 ) \
		|| bad "$pkg: archive does not match its .sha256 sidecar"

	[ "${sdist##*.}" = gz ] || continue
	rm -rf "$work/x"; mkdir -p "$work/x"
	tar -C "$work/x" -xf "$sdist" 2>/dev/null || true
	pp=$(find "$work/x" -maxdepth 2 -name pyproject.toml | head -1)
	[ -n "$pp" ] || continue
	be=$(awk -F'"' '/^build-backend/{print $2}' "$pp")
	haspath=$(awk '/^backend-path/{print "yes"}' "$pp")
	dep=setuptools
	[ -n "$haspath" ] || dep=$(backend_dep "$be")
	[ -n "$dep" ] || continue
	case "$dep" in
	\?*) bad "$pkg: unknown build backend $be" ;;
	*)
		grep -qE "^[[:space:]]*$dep$" "$d/recipe.sh" \
			|| bad "$pkg: build backend ${be:-setuptools} needs $dep in makedepends"
		;;
	esac
done

printf 'python-recipes: %d in-scope checked, %d problem(s); %d legacy python-* recipes out of scope\n' \
	"$checked" "$fail" "$legacy"
[ "$fail" -eq 0 ]

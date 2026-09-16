#!/bin/sh

# recipe-coverage.sh - the migration gate: every reference package
# recipe accounted for, exactly once.
#
# /reference-package-recipes is the authoritative migration input,
# /recipes the authoritative native output. Each reference recipe
# (any <name>/recipe.sh under the reference root) must have exactly
# one outcome: a same-name native recipe (no entry needed), an
# explicit rename/consolidation mapping, or an explicit reviewed
# exemption - both recorded in saphira-packager/files/recipe-coverage.map.
#
# Answers one question only: have ALL reference package recipes been
# accounted for? Exits non-zero until the answer is yes. No BLOCKED_BY
# concept: a missing dependency is an ordinary queue item for the
# builder, never an exemption.
#
# usage: recipe-coverage.sh (no arguments)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RECIPES=${SAPHIRA_COVERAGE_RECIPES:-$source_root}
REFERENCE=${SAPHIRA_COVERAGE_REFERENCE:-/reference-package-recipes}
MAPFILE=${SAPHIRA_COVERAGE_MAP:-$source_root/saphira-packager/files/recipe-coverage.map}

test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-coverage-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

problems=0
report()
{
	printf '%s\n' "$1"
	problems=$((problems + 1))
}

has_native()
{
	test -f "$2/$1/recipe.sh"
}

native_disabled()
{
	grep -q '^disabled=yes$' "$2/$1/recipe.sh" 2>/dev/null
}

has_reference()
{
	test -f "$2/$1/recipe.sh"
}

audit()
{
	# audit REFDIR NATIVEDIR MAPFILE - validate mapping, then report
	# every unexplained reference recipe. Accumulates $problems.
	refdir=$1
	nativedir=$2
	mapfile=$3
	test -f "$mapfile" || {
		report "coverage map is missing: $mapfile"
		return 0
	}
	seen_refs=" "
	lineno=0
	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		stripped=${line%%#*}
		case $stripped in
			'') continue ;;
		esac
		case $stripped in
			*[![:space:]]*) ;;
			*) continue ;;
		esac
		# shellcheck disable=SC2086
		set -- $stripped
		[ "$#" -ge 2 ] || {
			report "map line $lineno: malformed entry: $line"
			continue
		}
		ref=$1
		kind=$2
		case $seen_refs in
			*" $ref "*)
				report "map line $lineno: duplicate entry for '$ref'"
				continue
				;;
		esac
		seen_refs="$seen_refs$ref "
		case $kind in
			rename | consolidate)
				[ "$#" -eq 3 ] || {
					report "map line $lineno: $kind needs exactly a target: $line"
					continue
				}
				target=$3
				;;
			exempt)
				[ "$#" -eq 2 ] || {
					report "map line $lineno: exempt takes no target: $line"
					continue
				}
				target=
				;;
			*)
				report "map line $lineno: unknown kind '$kind': $line"
				continue
				;;
		esac
		has_reference "$ref" "$refdir" || {
			report "map line $lineno: no such reference recipe '$ref'"
			continue
		}
		if has_native "$ref" "$nativedir"; then
			report "map line $lineno: '$ref' has a same-name native recipe and needs no entry"
			continue
		fi
		if [ -n "$target" ]; then
			has_native "$target" "$nativedir" || {
				report "map line $lineno: mapping target missing: '$target' for '$ref'"
				continue
			}
			native_disabled "$target" "$nativedir" && {
				report "map line $lineno: mapping target disabled: '$target' for '$ref'"
				continue
			}
		fi
	done <"$mapfile"
	for frag in "$refdir"/*/recipe.sh; do
		[ -f "$frag" ] || continue
		ref=${frag%/*}
		ref=${ref##*/}
		has_native "$ref" "$nativedir" && continue
		case $seen_refs in
			*" $ref "*) continue ;;
		esac
		report "unexplained reference recipe: '$ref' (no native successor, mapping, or exemption)"
	done
}

# --- engine self-tests (fixture trees; the engine must catch every
# --- failure mode even while the real tree is red) ---
mkref()
{
	mkdir -p "$2/$1"
	printf '# fixture reference\n' > "$2/$1/recipe.sh"
}
mknat()
{
	mkdir -p "$2/$1"
	printf '# fixture native\n%s\n' "$3" > "$2/$1/recipe.sh"
}
expect_problems()
{
	want=$1
	shift
	problems=0
	audit "$@"
	[ "$problems" -eq "$want" ] || {
		printf 'coverage engine self-test failed: want %s problems, got %s (%s)\n' \
			"$want" "$problems" "$*" >&2
		exit 1
	}
}

T=$test_root/engine
# T1: all outcomes ok.
mkdir -p "$T/t1/ref" "$T/t1/nat"
mkref same "$T/t1/ref"
mknat same "$T/t1/nat" ""
mkref old "$T/t1/ref"
mknat new "$T/t1/nat" ""
mkref gone "$T/t1/ref"
printf '%s\n' 'old rename new' 'gone exempt' > "$T/t1/map"
expect_problems 0 "$T/t1/ref" "$T/t1/nat" "$T/t1/map"
# T2: unexplained reference fails, naming it.
mkdir -p "$T/t2/ref" "$T/t2/nat"
mkref mystery "$T/t2/ref"
printf '%s\n' '# empty map' > "$T/t2/map"
problems=0
audit "$T/t2/ref" "$T/t2/nat" "$T/t2/map" > "$T/t2.out" 2>&1
[ "$problems" -eq 1 ] || {
	printf 'coverage engine self-test T2 failed\n' >&2
	exit 1
}
grep -q "unexplained reference recipe: 'mystery'" "$T/t2.out" || {
	printf 'coverage engine self-test T2 naming failed\n' >&2
	exit 1
}
# T3..T7: each mapping defect fails exactly once.
mkdir -p "$T/t3/ref" "$T/t3/nat"
mkref old "$T/t3/ref"
printf '%s\n' 'old rename absent' > "$T/t3/map"
expect_problems 1 "$T/t3/ref" "$T/t3/nat" "$T/t3/map"
mkdir -p "$T/t4/ref" "$T/t4/nat"
mkref old "$T/t4/ref"
mknat new "$T/t4/nat" ""
printf '%s\n' 'old rename new' 'old exempt' > "$T/t4/map"
expect_problems 1 "$T/t4/ref" "$T/t4/nat" "$T/t4/map"
mkdir -p "$T/t5/ref" "$T/t5/nat"
mkref old "$T/t5/ref"
printf '%s\n' 'old frobnicate new' > "$T/t5/map"
expect_problems 1 "$T/t5/ref" "$T/t5/nat" "$T/t5/map"
mkdir -p "$T/t6/ref" "$T/t6/nat"
mkref same "$T/t6/ref"
mknat same "$T/t6/nat" ""
printf '%s\n' 'same rename same' > "$T/t6/map"
expect_problems 1 "$T/t6/ref" "$T/t6/nat" "$T/t6/map"
mkdir -p "$T/t7/ref" "$T/t7/nat"
mkref old "$T/t7/ref"
mknat new "$T/t7/nat" "disabled=yes"
printf '%s\n' 'old rename new' > "$T/t7/map"
expect_problems 1 "$T/t7/ref" "$T/t7/nat" "$T/t7/map"
printf '%s\n' 'coverage engine self-tests: OK'

# --- the real audit: non-zero until every reference is accounted for ---
problems=0
audit "$REFERENCE" "$RECIPES" "$MAPFILE"
if [ "$problems" -gt 0 ]; then
	printf 'recipe-coverage: FAIL: %s unaccounted reference package(s) (see above)\n' "$problems" >&2
	exit 1
fi
printf '%s\n' 'recipe-coverage: OK: every reference package recipe is accounted for'

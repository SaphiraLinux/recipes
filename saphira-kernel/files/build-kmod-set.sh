#!/bin/sh
# build-kmod-set.sh — rebuild kernel-module recipes for all kernels in
# one go. Stops at the first failure (fail closed; the retained
# workspace keeps the evidence).
#
# kmod builds are self-contained: each recipe prepares its kernel tree
# inside the worker (published config + sibling sources) and compiles
# its modules under /build. There is no staging step and no outdir:
# a second argument is refused loudly (the retired stage-kmod-input.sh
# flow is gone; see the removal note in the recipe history).
#
# Usage (run from anywhere; only absolute paths and PATH tools are used):
#   build-kmod-set.sh <family>               whole family, all kernels
#     e.g. build-kmod-set.sh nvidia-open
#          build-kmod-set.sh saphira-zfs
#   build-kmod-set.sh <family>-<kver>        one recipe only
#     e.g. build-kmod-set.sh nvidia-open-7.2.2
#   build-kmod-set.sh <kver>                 every family for one kernel
#     e.g. build-kmod-set.sh 7.2.2
#
# Shared (kernel-independent) recipes build first when their directories
# exist: <family>-firmware, then <family>-userspace.

set -eu

die()
{
	printf 'build-kmod-set: %s\n' "$*" >&2
	exit 1
}

list_families()
{
	for dir in /recipes/*-[0-9]*.[0-9]*/recipe.sh; do
		[ -f "$dir" ] || continue
		base=$(basename "$(dirname -- "$dir")")
		printf '%s\n' "$base" | sed -E 's/-[0-9]+\.[0-9]+(\.[0-9]+)?(-rc[0-9]+)?$//'
	done | sort -u | tr '\n' ' '
}

# Split a per-kernel recipe name into "family kver". Prints nothing and
# fails when the name does not end in a kernel version (this is what
# keeps nvidia-open-firmware and saphira-zfs-userspace out of family
# mode: their suffixes are words, not kernel versions).
split_recipe()
{
	family=$(printf '%s\n' "$1" | sed -E 's/-[0-9]+\.[0-9]+(\.[0-9]+)?(-rc[0-9]+)?$//')
	[ "$family" != "$1" ] || return 1
	suffix=${1#"$family"-}
	case $suffix in
		''|[!0-9]*|*[!0-9.A-Za-z_-]*|*..*) return 1 ;;
	esac
	printf '%s %s\n' "$family" "$suffix"
}

usage()
{
	printf 'build-kmod-set: usage: %s <family|family-kver|kver>\n' "$0" >&2
	printf 'build-kmod-set: known families: %s\n' "$(list_families)" >&2
	exit 1
}

is_kver()
{
	case $1 in
		[0-9]*.[0-9]*)
			case $1 in
				''|*[!0-9.A-Za-z_-]*) return 1 ;;
			esac
			return 0
			;;
		*) return 1 ;;
	esac
}

[ "$#" -eq 1 ] || {
	[ "$#" -eq 2 ] && die "an outdir argument means the retired staging flow (stage-kmod-input.sh is removed): kmod builds take no input directory; run: $0 $1"
	usage
}
what=$1
case $what in
	''|*[!A-Za-z0-9._+-]*) usage ;;
esac

# Validate the target before building anything: full recipe name, bare
# kernel with recipes, family with children, or a directly named recipe.
valid=0
if split_out=$(split_recipe "$what") && [ -d "/recipes/$what" ]; then
	valid=1
elif is_kver "$what"; then
	for dir in /recipes/*-"$what"/recipe.sh; do
		[ -f "$dir" ] && valid=1 && break
	done
else
	for dir in /recipes/"$what"-*/recipe.sh; do
		[ -f "$dir" ] && valid=1 && break
	done
	[ -f "/recipes/$what/recipe.sh" ] && valid=1
fi
[ "$valid" -eq 1 ] ||
	die "unknown family, recipe or kernel: $what (known families: $(list_families))"

build_shared()
{
	for shared in "$1-firmware" "$1-userspace"; do
		[ -f "/recipes/$shared/recipe.sh" ] || continue
		printf 'build-kmod-set: building shared %s\n' "$shared"
		buildpkg "$shared" || die "shared build failed: $shared"
	done
}

build_one()
{
	[ -f "/recipes/$1-$2/recipe.sh" ] ||
		die "no recipe: /recipes/$1-$2/recipe.sh (known families: $(list_families))"
	printf 'build-kmod-set: building %s-%s\n' "$1" "$2"
	buildpkg "$1-$2" || die "kernel build failed: $1-$2"
}

# Full per-kernel recipe name: build just that one (shared first).
if split_out=$(split_recipe "$what") && [ -d "/recipes/$what" ]; then
	set -- $split_out
	base=$1
	kver=$2
	build_shared "$base"
	build_one "$base" "$kver"
	printf 'build-kmod-set: done: %s-%s\n' "$base" "$kver"
	exit 0
fi

# Bare kernel version: every family that has a recipe for it.
if is_kver "$what"; then
	built=0
	for dir in /recipes/*-"$what"/recipe.sh; do
		[ -f "$dir" ] || continue
		family=$(basename "$(dirname -- "$dir")")
		family=${family%-"$what"}
		split_recipe "$family-$what" >/dev/null || continue
		build_shared "$family"
		build_one "$family" "$what"
		built=$((built + 1))
	done
	[ "$built" -gt 0 ] || die "no recipes for kernel $what (known families: $(list_families))"
	printf 'build-kmod-set: done: %d familie(s) for kernel %s\n' "$built" "$what"
	exit 0
fi

# Family name (has per-kernel children), or a directly named recipe.
# A same-named recipe dir (possibly disabled/retired) never shadows
# family mode: children decide.
have_children=0
for dir in /recipes/"$what"-*/recipe.sh; do
	[ -f "$dir" ] || continue
	child=$(basename "$(dirname -- "$dir")")
	split_recipe "$child" >/dev/null || continue
	have_children=1
	break
done
if [ "$have_children" -eq 0 ]; then
	if [ -f "/recipes/$what/recipe.sh" ]; then
		printf 'build-kmod-set: building shared %s\n' "$what"
		buildpkg "$what" || die "shared build failed: $what"
		printf 'build-kmod-set: done: shared %s\n' "$what"
		exit 0
	fi
	die "unknown family or recipe: $what (known families: $(list_families))"
fi

# Family name: shared first, then every per-kernel child in version order.
build_shared "$what"
built=0
for dir in /recipes/"$what"-*/recipe.sh; do
	[ -f "$dir" ] || continue
	child=$(basename "$(dirname -- "$dir")")
	split_out=$(split_recipe "$child") || continue
	set -- $split_out
	# $1 is $what by construction (glob prefix); $2 is the kver.
	build_one "$1" "$2"
	built=$((built + 1))
done
[ "$built" -gt 0 ] || die "no per-kernel recipes for family $what"
printf 'build-kmod-set: done: %d kernel build(s) for %s\n' "$built" "$what"

#!/bin/sh
# build-kmod-set.sh — rebuild kernel-module recipes for staged kernels in
# one go: stage inputs once, then build. Stops at the first failure
# (fail closed; the retained workspace keeps the evidence).
#
# Usage (run from anywhere; only absolute paths and PATH tools are used):
#   build-kmod-set.sh <family> [outdir]          whole family, all kernels
#     e.g. build-kmod-set.sh nvidia-open
#          build-kmod-set.sh saphira-zfs /build/zfs-input
#   build-kmod-set.sh <family>-<kver> [outdir]   one recipe only
#     e.g. build-kmod-set.sh nvidia-open-7.2.2
#   build-kmod-set.sh <kver> [outdir]            every family for one kernel
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
# fails when the name does not end in a kernel version.
split_recipe()
{
	family=$(printf '%s\n' "$1" | sed -E 's/-[0-9]+\.[0-9]+(\.[0-9]+)?(-rc[0-9]+)?$//')
	[ "$family" != "$1" ] || return 1
	printf '%s %s\n' "$family" "${1#"$family"-}"
}

usage()
{
	printf 'build-kmod-set: usage: %s <family|family-kver|kver> [outdir]\n' "$0" >&2
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

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
what=$1
outdir=${2:-/build/kernel-input}
case $what in
	''|*[!A-Za-z0-9._+-]*) usage ;;
esac

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -x "$here/stage-kmod-input.sh" ] || die "staging script missing beside $0"

# Validate the target before touching mounts: full recipe name, bare
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

"$here/stage-kmod-input.sh" "$outdir" || die "input staging failed"

build_shared()
{
	for shared in "$1-firmware" "$1-userspace"; do
		[ -f "/recipes/$shared/recipe.sh" ] || continue
		printf 'build-kmod-set: building shared %s\n' "$shared"
		buildpkg "$shared" "$outdir" || die "shared build failed: $shared"
	done
}

build_one()
{
	[ -f "/recipes/$1-$2/recipe.sh" ] ||
		die "no recipe: /recipes/$1-$2/recipe.sh (known families: $(list_families))"
	printf 'build-kmod-set: building %s-%s\n' "$1" "$2"
	buildpkg "$1-$2" "$outdir" || die "kernel build failed: $1-$2"
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
	[ -f "$dir" ] && have_children=1 && break
done
if [ "$have_children" -eq 0 ]; then
	if [ -f "/recipes/$what/recipe.sh" ]; then
		printf 'build-kmod-set: building shared %s\n' "$what"
		buildpkg "$what" "$outdir" || die "shared build failed: $what"
		printf 'build-kmod-set: done: shared %s\n' "$what"
		exit 0
	fi
	die "unknown family or recipe: $what (known families: $(list_families))"
fi

# Family name: shared first, then every staged kernel in version order.
build_shared "$what"
built=0
for tree in "$outdir"/linux-*/; do
	[ -d "$tree" ] || continue
	kver=${tree%/}
	kver=${kver#$outdir/linux-}
	[ -f "/recipes/$what-$kver/recipe.sh" ] ||
		die "staged kernel $kver has no recipe: /recipes/$what-$kver/recipe.sh (add one: new-kmod-variant.sh $what $kver; known families: $(list_families))"
	build_one "$what" "$kver"
	built=$((built + 1))
done
[ "$built" -gt 0 ] || die "no staged kernel trees under $outdir"
printf 'build-kmod-set: done: %d kernel build(s) for %s\n' "$built" "$what"

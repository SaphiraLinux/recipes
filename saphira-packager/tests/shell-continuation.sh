#!/bin/sh

# Shell continuation contract: no comment line may directly follow a
# backslash-newline continuation in any recipe.sh.
#
# Root cause it locks in (2026-10-23, util-linux r8): the shell joins
# the flag line with the comment line, the `#' swallows the rest of
# that logical line, and every later flag becomes a command (`-DFOO:
# command not found'). util-linux shipped meson only its first nine
# flags, so libmount/python never saw its disable and the build died
# on the missing python3-dev -- while a quieter variant of the same
# truncation once deleted fdisk/sfdisk silently. Proven by stub
# reproduction and the retained meson-log Build Options line.
#
# usage: shell-continuation.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

failures=0
for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	pkg=${recipe#"$source_root"/}
	hit=$(awk 'prev_bs && /^[[:space:]]*#/ {print FNR": "$0} {prev_bs = ($0 ~ /\\$/)}' "$recipe") || true
	if [ -n "$hit" ]; then
		printf 'FAIL     %s has a comment inside a backslash continuation:\n%s\n' "$pkg" "$hit" >&2
		failures=$((failures + 1))
	fi
done

if [ "$failures" -gt 0 ]; then
	printf 'shell-continuation: %d file(s) with truncated continuations\n' "$failures" >&2
	exit 1
fi
printf 'ok       shell continuations are comment-free\n'

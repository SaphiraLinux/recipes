#!/bin/sh

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

printf '%s\n' 'buildpkg worker isolation guard: OK'

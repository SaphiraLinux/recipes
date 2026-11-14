#!/bin/sh
# Registered offline source validation. No host build, install, or network.
set -eu
source_dir=${SYSREF_SOURCE_DIR:-/home/smalley/saphira-sysref}
test_root=$(mktemp -d "${SAPHIRA_TMPDIR:-/build/tmp}/sysref-test.XXXXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
cp -R "$source_dir/src" "$source_dir/tests" "$test_root/"
bwrap --unshare-all --die-with-parent --ro-bind / / --bind "$test_root" "$test_root" --dev /dev --proc /proc --chdir "$test_root" --setenv TMPDIR "$test_root" sh -eu -c '
 gcc -std=gnu11 -O2 -Wall -Wextra -Werror src/main.c src/core.c src/mcp.c src/json.c src/api.c -o sysref
 python3 tests/symbol_api.py "$PWD/sysref" "$PWD"
'

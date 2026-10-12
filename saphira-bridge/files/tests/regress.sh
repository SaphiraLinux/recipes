#!/bin/sh
# saphira-bridge rootless regression suite. BUSL-1.1, see LICENSE
#
# Self-contained: builds in a temporary directory, needs no privileges, no
# network and no kernel cooperation. The privileged proof that forwarding and
# learning are correct is tests/bridge-lab.sh, which builds its own namespaces.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/br-regress.XXXXXX") || exit 1
pass=0
fail=0
BIN="$TMP/bin"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

say()  { printf '  %s\n' "$1"; }
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
group(){ printf '\n== %s\n' "$1"; }

# assert a command succeeds
okc() {
    if "$@" >"$TMP/out" 2>"$TMP/err"; then ok; else
        bad "$1"; sed 's/^/    /' "$TMP/err" | head -5
    fi
}
# assert a command fails
nok() {
    if "$@" >"$TMP/out" 2>"$TMP/err"; then bad "$1 (unexpectedly succeeded)"; else ok; fi
}

printf 'saphira-bridge rootless regression\n'

group "build"
mkdir -p "$BIN"
for f in "$ROOT"/src/*.c; do
    if ! cc -std=c11 -O1 -Wall -Wextra -Wpedantic -Werror \
        -D_DEFAULT_SOURCE -D_GNU_SOURCE -c "$f" -o "$BIN/$(basename "$f" .c).o" \
        >"$TMP/cc.log" 2>&1; then
        bad "compiles clean ($(basename "$f"))"
        sed 's/^/    /' "$TMP/cc.log" | head -20
    else ok; fi
done

if cc -std=c11 -O1 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE -D_GNU_SOURCE \
   -o "$BIN/saphira-bridge" "$ROOT"/src/*.c >"$TMP/link.log" 2>&1; then ok; else
    bad "links"; sed 's/^/    /' "$TMP/link.log" | head -20
fi
BR="$BIN/saphira-bridge"

if cc -std=c11 -O1 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE -D_GNU_SOURCE \
   -o "$BIN/unit" "$ROOT/tests/unit.c" "$ROOT/src/eth.c" "$ROOT/src/cam.c" \
   "$ROOT/src/fwd.c" >"$TMP/unitbuild.log" 2>&1; then ok; else
    bad "the unit suite compiles"; sed 's/^/    /' "$TMP/unitbuild.log" | head -20
fi
if cc -std=c11 -O1 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE -D_GNU_SOURCE \
   -o "$BIN/probe" "$ROOT/tests/br-probe.c" >"$TMP/probebuild.log" 2>&1; then ok; else
    bad "the test probe compiles"; sed 's/^/    /' "$TMP/probebuild.log" | head -20
fi

group "the daemon must not be a shell wrapper"
if grep -rlE 'system\(|popen\(|/bin/sh' "$ROOT/src"/*.c >/dev/null 2>&1; then
    bad "no process execution in src"
else ok; fi

group "no third-party dependency"
if command -v ldd >/dev/null 2>&1 && [ -x "$BR" ]; then
    libs=$(ldd "$BR" 2>/dev/null | grep -oE 'lib[a-z0-9_.+-]*\.so' | sort -u | tr '\n' ' ')
    say "linked against: ${libs:-unknown}"
    case "$libs" in
        *libcrypto*|*libssl*|*libpcap*|*libsystemd*) bad "links only libc" ;;
        *) ok ;;
    esac
else ok; fi

group "policy core"
if [ -x "$BIN/unit" ]; then
    "$BIN/unit" >"$TMP/unit.out" 2>&1
    okc "$BIN/unit"
    sed 's/^/  /' "$TMP/unit.out"
fi

group "configuration through the binary"
cat >"$TMP/good.conf" <<'EOF'
# three point-to-point links joined into one segment
port=lan0
port=lan1
port=lan2
age_secs=300
max_entries=4096
EOF
okc "$BR" -c "$TMP/good.conf" -n regress --check

printf 'port=lan0\n' >"$TMP/one.conf"
nok "$BR" -c "$TMP/one.conf" --check
say "one port cannot join anything to anything"

printf 'port=lan0\nport=lan0\n' >"$TMP/dup.conf"
nok "$BR" -c "$TMP/dup.conf" --check
say "a repeated port would make the ingress port ambiguous"

printf 'port=lan0\nport=lan1\nbogus=1\n' >"$TMP/unknown.conf"
nok "$BR" -c "$TMP/unknown.conf" --check
say "an unknown key is refused rather than ignored"

printf 'port=lan0\nport=lan1\nage_secs=0\n' >"$TMP/age0.conf"
nok "$BR" -c "$TMP/age0.conf" --check
say "a zero idle age is refused"

printf 'port=lan0\nport=lan1\nmax_entries=1\n' >"$TMP/tiny.conf"
nok "$BR" -c "$TMP/tiny.conf" --check
say "an unusably small table is refused"

printf 'port=lan0\nport=lan1\nmax_entries=999999\n' >"$TMP/huge.conf"
nok "$BR" -c "$TMP/huge.conf" --check
say "an unbounded table is refused"

printf 'port=lan0\nport=lan1\nport lan2\n' >"$TMP/nokey.conf"
nok "$BR" -c "$TMP/nokey.conf" --check
say "a line without key=value is refused"

printf 'port=lan0\nport=../../etc/passwd\n' >"$TMP/traverse.conf"
nok "$BR" -c "$TMP/traverse.conf" --check
say "a name that is not an interface name is refused"

nok "$BR" --check
say "-c is required"

nok "$BR" -c /nonexistent/path.conf --check
say "a missing configuration file is refused"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

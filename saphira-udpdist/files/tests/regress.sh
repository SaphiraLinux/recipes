#!/bin/sh
# saphira-udpdist regression suite. Rootless, seconds to run.
# Every check here is able to fail; a passing run is meaningful.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/udpdist-regress.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
group=""

say_group() { group="$1"; printf '== %s\n' "$1"; }

ok() {
    pass=$((pass + 1))
    [ "$1" -eq 0 ] || { fail=$((fail + 1)); printf '  FAIL [%s] %s\n' "$group" "$2"; }
}

say_group "build"
make -C "$ROOT/src" >"$TMP/build.log" 2>&1
ok $? "the daemon and the lab tools compile"
if [ -s "$TMP/build.log" ] && grep -qi 'warning' "$TMP/build.log"; then
    fail=$((fail + 1))
    printf '  FAIL [%s] the build emitted warnings\n' "$group"
    grep -i warning "$TMP/build.log" | sed 's/^/    /'
else
    pass=$((pass + 1))
fi

say_group "no shell, ever"
# A service name reaches logs and is derived from the -c path. There must be no
# path from any input to /bin/sh.
if grep -nE '\b(system|popen|execl|execlp|execv|execvp|execle|posix_spawn)\s*\(' \
        "$ROOT"/src/*.c >"$TMP/shell.txt" 2>/dev/null; then
    fail=$((fail + 1))
    printf '  FAIL [%s] a process-spawning call is present in the daemon:\n' "$group"
    sed 's/^/    /' "$TMP/shell.txt"
else
    pass=$((pass + 1))
fi

say_group "no nftables fast path"
if grep -niE 'nft|iptables|ebtables|nftables' "$ROOT"/src/*.c >"$TMP/nft.txt" 2>/dev/null; then
    fail=$((fail + 1))
    printf '  FAIL [%s] firewall tooling is referenced; a fast path must not be claimed\n' "$group"
    sed 's/^/    /' "$TMP/nft.txt"
else
    pass=$((pass + 1))
fi

say_group "unit suite"
cc -std=c11 -O1 -Wall -Wextra -Wno-unused-parameter -D_DEFAULT_SOURCE -D_GNU_SOURCE \
   -o "$TMP/unit" "$ROOT/tests/unit.c" \
   "$ROOT/src/frame.c" "$ROOT/src/hrw.c" "$ROOT/src/frag.c" \
   "$ROOT/src/quic.c" "$ROOT/src/config.c" "$ROOT/src/neigh.c" >"$TMP/cc.log" 2>&1
ok $? "the unit suite compiles"
if [ -x "$TMP/unit" ]; then
    "$TMP/unit" >"$TMP/unit.out" 2>"$TMP/unit.err"
    ok $? "unit checks"
    sed 's/^/  /' "$TMP/unit.out"
    [ -s "$TMP/unit.err" ] && { printf '  (diagnostics on stderr)\n'; sed 's/^/    /' "$TMP/unit.err"; }
fi

say_group "configuration validation through the binary"
cat >"$TMP/good.conf" <<'EOF'
frontend=10.0.0.2:53 iface=lo proto=udp
backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01
backend=10.0.0.12:9000 mac=aa:bb:cc:00:00:02
EOF
"$ROOT/src/udpdist" --check -c "$TMP/good.conf" >/dev/null 2>&1
ok $? "a valid configuration is accepted by --check"

cat >"$TMP/bad.conf" <<'EOF'
frontend=10.0.0.2:53 proto=quic quic_mode=quic_lb
backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01
EOF
"$ROOT/src/udpdist" --check -c "$TMP/bad.conf" >/dev/null 2>&1
[ $? -ne 0 ]
ok $? "quic_lb without CID configuration is refused"

cat >"$TMP/mac.conf" <<'EOF'
frontend=10.0.0.2:53 iface=lo
backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01
require_mac=0
EOF
"$ROOT/src/udpdist" --check -c "$TMP/mac.conf" >/dev/null 2>&1
ok $? "require_mac=0 still needs a mac in practice (parse only)"

cat >"$TMP/auto.conf" <<'EOF'
frontend=10.0.0.2:53 iface=lo
backend=10.0.0.11:9000 mac=auto
backend=10.0.0.12:9000 mac=auto
require_mac=1
EOF
"$ROOT/src/udpdist" --check -c "$TMP/auto.conf" >/dev/null 2>&1
ok $? "mac=auto satisfies require_mac: the address is resolved before traffic, not written down"

cat >"$TMP/auto2.conf" <<'EOF'
frontend=10.0.0.2:53 iface=lo
backend=10.0.0.11:9000
require_mac=1
EOF
[ "$("$ROOT/src/udpdist" --check -c "$TMP/auto2.conf" >/dev/null 2>&1; echo $?)" -ne 0 ]
ok $? "a backend with no mac and no mac=auto is still refused under require_mac"

# Parsing must not try to resolve: --check has no business needing a live
# neighbour table, and a parse-time lookup would make offline validation of a
# config impossible. The gate that matters is at real start, where
# validate_backends() refuses to serve until a usable address exists in hand.
cat >"$TMP/auto3.conf" <<'EOF'
frontend=10.0.0.2:53 iface=lo
backend=10.0.0.11:9000 mac=auto
EOF
"$ROOT/src/udpdist" --check -c "$TMP/auto3.conf" >/dev/null 2>&1
ok $? "mac=auto is parsed without attempting a neighbour lookup, so a config can be validated offline"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0

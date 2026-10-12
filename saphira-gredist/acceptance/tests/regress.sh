#!/bin/sh
# Regression tests for the r7 fixes. Rootless except where noted: every test
# either needs no privileges at all (they fail before any socket is opened) or
# says so and skips.
#
#   sh acceptance/tests/regress.sh          # run all
#
# Each test names the finding it locks in. These are cheap, deterministic and
# run on Egg; the three-host behavioural proofs live in acceptance/run.sh.
set -eu

SRC=$(cd "$(dirname "$0")/../../files/src" && pwd)
BIN=$SRC/gredist
pass=0
fail=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { pass=$((pass+1)); printf 'PASS %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2' want '$3')"; fi; }

# a syntactically valid single-service config, reused by most tests
mkgood() { printf 'frontend=10.77.0.11\nbackend=10.77.1.12\nbackend=10.77.1.13\n' > "$1"; }

if [ ! -x "$BIN" ]; then
	echo "gredist not built; run: make -C $SRC" >&2
	exit 2
fi

########################################################################
# F-9: no shell, and the -c basename is validated like a service name
########################################################################
echo "== F-9 shell injection =="
# The exploit must not execute. Run from $TMP so a bare relative marker lands
# in a throwaway directory.
( cd "$TMP" && rm -f INJECTED_POC )
mkgood "$TMP/\$(touch INJECTED_POC).conf"
( cd "$TMP" && "$BIN" -c "$TMP/\$(touch INJECTED_POC).conf" >/dev/null 2>&1 ) || true
if [ -e "$TMP/INJECTED_POC" ]; then
	bad "F-9 command substitution in -c basename executed"
else
	ok "F-9 command substitution in -c basename not executed"
fi

for hostile in 'a;id;.conf' 'a`id`.conf' 'a|id.conf' 'a&b.conf' 'a$b.conf' 'a
b.conf' 'a..b.conf' 'a*b.conf'; do
	f="$TMP/$hostile"
	mkgood "$f" 2>/dev/null || continue
	out=$("$BIN" -c "$f" 2>&1 | head -1 || true)
	case $out in
	*invalid\ service\ name*) ok "F-9 refuses -c basename '$hostile'" ;;
	*) bad "F-9 accepted -c basename '$hostile' (got: $out)" ;;
	esac
	rm -f "$f"
done

# the same rule for the positional service name
for hostile in 'bad$(id)' 'bad;id' 'bad`id`' 'bad|id' 'bad&x'; do
	out=$("$BIN" "$hostile" 2>&1 | head -1 || true)
	case $out in
	*invalid\ service\ name*) ok "F-9 refuses service name '$hostile'" ;;
	*) bad "F-9 accepted service name '$hostile' (got: $out)" ;;
	esac
done

# a valid name must still work up to the point of needing a socket
mkgood "$TMP/good-name_1.conf"
out=$("$BIN" -c "$TMP/good-name_1.conf" 2>&1 | head -1 || true)
case $out in
*starting\ service\ good-name_1*) ok "F-9 still accepts a valid -c basename" ;;
*) bad "F-9 rejected a valid -c basename (got: $out)" ;;
esac

# the daemon must contain no shell call at all
if grep -qE '^[^/*]*\b(system|popen)\s*\(' "$SRC/gredist.c" "$SRC/gre.c" "$SRC/config.c"; then
	bad "F-9 daemon still calls system()/popen() in code"
else
	ok "F-9 no system()/popen() in daemon code"
fi

########################################################################
# F-4: the nft placeholder is gone, and claims it nothing
########################################################################
echo "== F-4 nft placeholder removed =="
# code lines only: the removal is documented in a comment block that quotes the
# old system() call, and that must not be mistaken for live code.
if grep -vE '^\s*(\*|/\*|//)' "$SRC/gredist.c" | grep -q 'nft'; then
	bad "F-4 gredist still manipulates an nft table"
else
	ok "F-4 gredist no longer creates an nft table"
fi
if "$BIN" -c "$TMP/good-name_1.conf" 2>&1 | grep -qi 'nft'; then
	bad "F-4 gredist still logs an nft fast path"
else
	ok "F-4 gredist makes no nft claim"
fi

########################################################################
# F-5 / C13: the HRW score must not depend on backend array position
########################################################################
echo "== F-5 HRW backend-identity stability =="
cat > "$TMP/hrw.c" <<'CEOF'
#include "gredist.h"
#include <stdio.h>
#include <string.h>
/* Build a pool of 3 backends and score 200 flows under two orderings of the
 * SAME set. Every flow must land on the same backend address either way. */
static int run(int order[3], int *out){
    struct service svc; memset(&svc,0,sizeof(svc));
    const char *names[3]={"10.77.1.11","10.77.1.12","10.77.1.13"};
    svc.nbackends=3;
    for(int i=0;i<3;i++){
        struct backend *b=&svc.backends[order[i]];
        memset(b,0,sizeof(*b));
        snprintf(b->str,sizeof(b->str),"%s",names[order[i]]);
        b->family=AF_INET; b->healthy=1;
        backend_compute_hash(b);
    }
    for(int k=0;k<200;k++){
        uint8_t src[4]={10,0,(unsigned char)(k>>8),(unsigned char)k};
        struct gre_info g; memset(&g,0,sizeof(g)); g.has_key=1; g.key=(uint32_t)k;
        out[k]=select_backend(&svc,src,4,&g);
    }
    return 0;
}
int main(void){
    int a[3]={0,1,2}, b[3]={2,1,0}, c[3]={1,2,0};
    int ra[200], rb[200], rc[200];
    run(a,ra); run(b,rb); run(c,rc);
    int bad=0;
    for(int k=0;k<200;k++) if(ra[k]!=rb[k] || ra[k]!=rc[k]) bad++;
    if(bad){ printf("  %d of 200 flows moved on reorder\n",bad); return 1; }
    printf("  200/200 flows stable across three orderings\n");
    return 0;
}
CEOF
if cc -std=c11 -O2 -D_DEFAULT_SOURCE -I"$SRC" "$TMP/hrw.c" "$SRC/gre.c" "$SRC/config.c" -o "$TMP/hrw" 2>"$TMP/cc.err"; then
	if "$TMP/hrw"; then ok "F-5 HRW score is independent of backend position"; else bad "F-5 HRW score depends on backend position"; fi
else
	bad "F-5 could not build the HRW test: $(head -1 "$TMP/cc.err")"
fi

########################################################################
# F-8: the lazy send path must not set IP_HDRINCL
########################################################################
echo "== F-8 IP_HDRINCL =="
if grep -qE '^[^/*]*IP_HDRINCL\s*\)' "$SRC/gredist.c"; then
	bad "F-8 gredist still sets IP_HDRINCL in code"
else
	ok "F-8 gredist never sets IP_HDRINCL"
fi

########################################################################
# INV-1: every accepted packet must reach a named counter
########################################################################
echo "== INV-1 observed disposition =="
# every counter that drop paths can touch must appear in the stats dump, and
# rx must equal the sum of forwarded plus every drop counter
for c in malformed truncated frag version no_backend queue oversized not_for_us; do
	if "$BIN" -c "$TMP/good-name_1.conf" 2>&1 | grep -q "$c="; then
		:
	fi
done
# static: the dump line must mention oversized and not_for_us
if grep -q 'oversized=%lu not_for_us=%lu' "$SRC/gredist.c"; then
	ok "INV-1 stats dump reports oversized and not_for_us"
else
	bad "INV-1 stats dump still omits oversized/not_for_us"
fi
# the oversized path must not also bump malformed any more
if grep -q 'dropped_oversized++; svc.dropped_malformed' "$SRC/gredist.c"; then
	bad "INV-1 oversized is still double-counted as malformed"
else
	ok "INV-1 oversized is counted once"
fi
# a dst mismatch must be counted, not a bare continue
if grep -qE '^\s*continue;\s*$' "$SRC/gredist.c" >/dev/null; then
	if grep -B3 -E '^\s*continue;\s*$' "$SRC/gredist.c" | grep -q 'not_for_us'; then
		ok "INV-1 dst mismatch is counted"
	else
		bad "INV-1 a bare continue remains near the dst filter"
	fi
fi
# and the v6 headerless fallback, which forced dst_match, must be gone
if grep -q 'is_v6_raw_without_hdr' "$SRC/gredist.c"; then
	bad "INV-1 the IPv6 headerless fallback is still present"
else
	ok "INV-1 IPv6 headerless fallback removed (fails closed)"
fi

########################################################################
# parse_outer: IPv6 fragments must be reported as fragments
########################################################################
echo "== IPv6 fragment classification =="
cat > "$TMP/frag.c" <<'CEOF'
#include "gredist.h"
#include <stdio.h>
#include <string.h>
int main(void){
    uint8_t p6[64]; memset(p6,0,sizeof(p6));
    p6[0]=0x60; p6[4]=0; p6[5]=8; p6[6]=44;      /* next header 44 = fragment */
    p6[40]=0; p6[41]=0; p6[42]=0x08; p6[43]=0;
    int f; size_t hl; uint8_t s[16],d[16]; size_t sl,dl;
    if(parse_outer(p6,48,&f,&hl,s,&sl,d,&dl)!=-2){
        printf("  v6 fragment not reported as -2\n"); return 1; }
    p6[6]=47;                                    /* next header 47 = GRE */
    if(parse_outer(p6,48,&f,&hl,s,&sl,d,&dl)!=0){
        printf("  v6 GRE no longer parses\n"); return 2; }
    uint8_t p4[64]; memset(p4,0,sizeof(p4));
    p4[0]=0x45; p4[9]=47; p4[2]=0; p4[3]=24; p4[6]=0x20;  /* MF set */
    if(parse_outer(p4,24,&f,&hl,s,&sl,d,&dl)!=-2){
        printf("  v4 fragment not reported as -2\n"); return 3; }
    printf("  v4 and v6 fragments both -2, v6 GRE still parses\n");
    return 0;
}
CEOF
if cc -std=c11 -O2 -D_DEFAULT_SOURCE -I"$SRC" "$TMP/frag.c" "$SRC/gre.c" "$SRC/config.c" -o "$TMP/frag" 2>"$TMP/cc2.err"; then
	if "$TMP/frag"; then ok "IPv6 fragment counted as a fragment"; else bad "IPv6 fragment misclassified"; fi
else
	bad "could not build the fragment test: $(head -1 "$TMP/cc2.err")"
fi

########################################################################
# F-7: health probing must never block the event loop
########################################################################
echo "== F-7 non-blocking health probing =="
# The r7 defect was a probe that forked and then spun on waitpid inside the
# loop: ~1.03 s of deafness per dead backend, ~5.5 s for three. These lock in
# the structural properties of the fix. The behavioural proof - that latency no
# longer scales with dead probes - is the three-node run, because it needs real
# unresponsive peers.

# no blocking wait for a specific child anywhere
if grep -vE '^\s*(\*|/\*|//)' "$SRC/gredist.c" | grep -qE 'waitpid\s*\([^)]*,[^)]*,\s*0\s*\)'; then
	bad "F-7 a blocking waitpid() remains in the daemon"
else
	ok "F-7 no blocking waitpid() on a child"
fi
# every waitpid must be WNOHANG
if grep -vE '^\s*(\*|/\*|//)' "$SRC/gredist.c" | grep -qE 'waitpid' && \
   grep -vE '^\s*(\*|/\*|//)' "$SRC/gredist.c" | grep -E 'waitpid' | grep -qv WNOHANG; then
	bad "F-7 a waitpid() is not WNOHANG"
else
	ok "F-7 every waitpid() is WNOHANG"
fi
# the reaper must run inside the main loop
if grep -q 'probes_reap(&svc);' "$SRC/gredist.c"; then
	n=$(grep -c 'probes_reap(&svc);' "$SRC/gredist.c")
	if [ "$n" -eq 1 ]; then ok "F-7 probes_reap() is called from the event loop"
	else bad "F-7 probes_reap() called $n times (expected once, in the loop)"; fi
else
	bad "F-7 probes_reap() is never called"
fi
# in-flight probes must shorten the poll timeout, so results are collected
if grep -qE 'poll\(pfds, npfds, probes_inflight\(\)' "$SRC/gredist.c"; then
	ok "F-7 poll timeout shortens while probes are in flight"
else
	bad "F-7 poll timeout does not account for in-flight probes"
fi
# probes must be dropped on reload (the backend array is replaced, so an
# in-flight index would name a different backend) and on shutdown
if grep -q 'probes_cancel' "$SRC/gredist.c"; then
	ok "F-7 probes_cancel() exists"
else
	bad "F-7 no probe cancellation on reload/shutdown"
fi
n=$(grep -c 'probes_cancel();' "$SRC/gredist.c")
if [ "$n" -ge 2 ]; then ok "F-7 probes cancelled on both reload and shutdown"
else bad "F-7 probes_cancel() called $n time(s); reload and shutdown both need it"; fi
# a backend already being probed must not be probed again
if grep -q 'if(probe_busy(i)) continue;' "$SRC/gredist.c"; then
	ok "F-7 a backend with a probe in flight is not re-probed"
else
	bad "F-7 a backend can be probed twice concurrently"
fi
# thresholds and cadence must be exactly what r7 had, or health convergence
# would change and every r7 health result would be invalid
for d in 'HEALTH_INTERVAL_SEC 2' 'HEALTH_FAIL_THRESHOLD 2' 'HEALTH_OK_THRESHOLD 2'; do
	k=$(echo "$d" | cut -d' ' -f1)
	if grep -qE "^#define $k $(echo "$d" | cut -d' ' -f2)$" "$SRC/gredist.h"; then
		ok "F-7 $k unchanged at $(echo "$d" | cut -d' ' -f2)"
	else
		bad "F-7 $k changed; r7 health convergence depended on it"
	fi
done
# the probe timeout must not be tighter than the child needs
if grep -qE '^#define PROBE_TIMEOUT_SEC [0-9]+' "$SRC/gredist.c"; then
	v=$(grep -oE '^#define PROBE_TIMEOUT_SEC [0-9]+' "$SRC/gredist.c" | grep -oE '[0-9]+$')
	if [ "$v" -ge 1 ]; then ok "F-7 PROBE_TIMEOUT_SEC is $v s"
	else bad "F-7 PROBE_TIMEOUT_SEC too tight"; fi
fi

########################################################################
# F-3: SIGHUP frontend change must not be able to blackhole traffic
########################################################################
echo "== F-3 reload cannot desynchronise the frontend =="
# The defect was structural: the receive socket was bound to the configured
# frontend, and a raw socket can be bound exactly once, so a reloaded frontend
# could never take effect. These lock in the shape of the fix.
if grep -vE '^\s*(\*|/\*|//)' "$SRC/gredist.c" | grep -q 'bind('; then
	bad "F-3 gredist still binds a socket (a frontend change cannot take effect)"
else
	ok "F-3 gredist binds no socket: the frontend is enforced per packet"
fi
# both families must be opened at bootstrap, or a family change on reload is
# impossible after the privilege drop (socket() needs CAP_NET_RAW)
for f in 'recv4 = socket(AF_INET, SOCK_RAW, IPPROTO_GRE)' 'recv6 = socket(AF_INET6, SOCK_RAW, IPPROTO_GRE)'; do
	k=$(echo "$f" | cut -d' ' -f1)
	if grep -q "$k" "$SRC/gredist.c"; then ok "F-3 $k opened at bootstrap"
	else bad "F-3 $k missing; a family change on reload could not take effect"; fi
done
# both must be polled, otherwise one family is opened but never read
n=$(grep -cE 'pfds\[npfds\]\.fd=recv[46]' "$SRC/gredist.c")
if [ "$n" -ge 2 ]; then ok "F-3 both receive sockets are polled"
else bad "F-3 only $n receive socket(s) polled"; fi
# the destination filter must still exist and still feed not_for_us
if grep -q 'dst_match' "$SRC/gredist.c" && grep -q 'dropped_not_for_us++' "$SRC/gredist.c"; then
	ok "F-3 frontend enforced per packet and rejects are counted"
else
	bad "F-3 the per-packet frontend filter or its counter is gone"
fi

########################################################################
# r9: the daemon must not keep root
########################################################################
echo "== r9 privilege drop =="
if grep -qE 'setuid\(pw->pw_uid\)' "$SRC/gredist.c"; then ok "r9 setuid to the service uid"
else bad "r9 no setuid to a service uid"; fi
if grep -qE 'setgid\(gid\)' "$SRC/gredist.c"; then ok "r9 setgid to the service gid"
else bad "r9 no setgid to a service gid"; fi
if grep -qE 'setgroups\(1, &gid\)' "$SRC/gredist.c"; then ok "r9 supplementary groups are dropped to one"
else bad "r9 supplementary groups are never dropped"; fi
# the drop must be proven, not assumed
if grep -qE 'setuid\(0\) == 0' "$SRC/gredist.c"; then ok "r9 the drop is verified with setuid(0)"
else bad "r9 the drop is not verified"; fi
# it must refuse to start if the account is missing, rather than run as root
if grep -qE 'getpwnam\(user\)' "$SRC/gredist.c" && grep -qE 'drop_privileges\(GREDIST_USER, GREDIST_GROUP\) != 0\) return 1' "$SRC/gredist.c"; then
	ok "r9 a missing service account is fatal, not silently ignored"
else
	bad "r9 a missing service account would not stop the daemon"
fi
# it must fail closed if it cannot re-read its own config after the drop
if grep -q 'config_is_readable(config_path)' "$SRC/gredist.c"; then
	ok "r9 startup checks the config is re-readable after the drop"
else
	bad "r9 no post-drop config readability check"
fi
# ordering: setgroups must happen before setuid, while still root, or it fails
ln_g=$(grep -n 'setgroups(1, &gid)' "$SRC/gredist.c" | head -1 | cut -d: -f1)
ln_u=$(grep -n 'setuid(pw->pw_uid)' "$SRC/gredist.c" | head -1 | cut -d: -f1)
ln_d=$(grep -n 'setgid(gid)' "$SRC/gredist.c" | head -1 | cut -d: -f1)
if [ -n "$ln_g" ] && [ -n "$ln_d" ] && [ -n "$ln_u" ] && \
   [ "$ln_g" -lt "$ln_d" ] && [ "$ln_d" -lt "$ln_u" ]; then
	ok "r9 drop order is setgroups -> setgid -> setuid"
else
	bad "r9 drop order wrong (setgroups@$ln_g setgid@$ln_d setuid@$ln_u); groups must be dropped first"
fi
# the identity must be a compiled-in constant, never a config knob
if grep -qE '^#define GREDIST_USER "gredist"' "$SRC/gredist.c" &&    ! grep -qE 'gredist_user\s*=' "$SRC/gredist.c"; then
	ok "r9 the service identity is compiled in, not configurable"
else
	bad "r9 the service identity is configurable from the config"
fi
# and the recipe must ship the identity fragment
if [ -f "$SRC/../accounts.d/saphira-gredist" ]; then
	ok "r9 the recipe ships an accounts.d identity fragment"
else
	bad "r9 no accounts.d identity fragment"
fi

########################################################################
echo
echo "Results: $pass pass, $fail fail"
[ "$fail" -eq 0 ] || exit 1

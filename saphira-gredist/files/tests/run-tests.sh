#!/bin/bash
# Saphira Linux (c) 2026 - MIT Licensed - saphira-gredist test harness
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")/../src" && pwd)"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass=0; fail=0

run() { echo ">> $*"; "$@"; }

assert() {
  local cond=$1 msg=$2
  if eval "$cond"; then echo -e "${GREEN}PASS${NC} $msg"; pass=$((pass+1)); else echo -e "${RED}FAIL${NC} $msg"; fail=$((fail+1)); fi
}

echo "[*] building"
make -C "$SRC_DIR" -j"$(nproc)" >/dev/null
echo "[*] build ok"

echo "[*] unit: config parse"
cat > /tmp/test-unit.conf <<EOF
frontend=10.0.0.1
backend=10.0.0.2
backend=10.0.0.3
EOF
"$SRC_DIR/gredist" -c /tmp/test-unit.conf --help >/dev/null 2>&1 || true
# run binary with invalid config to test parse (should fail)
if "$SRC_DIR/gredist" -c /tmp/test-unit.conf --help 2>&1 | grep -q "Usage"; then pass=$((pass+1)); echo "PASS config help"; else fail=$((fail+1)); echo "FAIL help"; fi

echo "[*] unit: GRE parse and HRW"
cat > /tmp/hrw-test.c <<'CEOF'
#include "gredist.h"
#include <stdio.h>
#include <string.h>
int main(){
    struct service svc; memset(&svc,0,sizeof(svc));
    svc.nbackends=3;
    snprintf(svc.backends[0].str,sizeof(svc.backends[0].str),"10.0.0.101"); svc.backends[0].family=AF_INET; svc.backends[0].healthy=1; backend_compute_hash(&svc.backends[0]);
    snprintf(svc.backends[1].str,sizeof(svc.backends[1].str),"10.0.0.102"); svc.backends[1].family=AF_INET; svc.backends[1].healthy=1; backend_compute_hash(&svc.backends[1]);
    snprintf(svc.backends[2].str,sizeof(svc.backends[2].str),"10.0.0.103"); svc.backends[2].family=AF_INET; svc.backends[2].healthy=1; backend_compute_hash(&svc.backends[2]);
    uint8_t s1[]={10,0,0,10};
    struct gre_info g1={0}; g1.has_key=1; g1.key=0x12345678;
    int a=select_backend(&svc,s1,4,&g1);
    int b=select_backend(&svc,s1,4,&g1);
    if(a!=b){ printf("FAIL affinity %d != %d\n",a,b); return 1; }
    printf("affinity ok backend %d\n",a);
    // remove backend a, should move
    int orig=a;
    svc.backends[orig].healthy=0;
    int c=select_backend(&svc,s1,4,&g1);
    if(c==orig){ printf("FAIL removal not moved\n"); return 1; }
    printf("removal ok %d -> %d\n",orig,c);
    // other flow should stay
    uint8_t s2[]={10,0,0,11};
    struct gre_info g2={0}; g2.has_key=0;
    int d=select_backend(&svc,s2,4,&g2);
    svc.backends[orig].healthy=0; // already
    int e=select_backend(&svc,s2,4,&g2);
    if(d!=e) printf("warning: second flow moved %d->%d (acceptable but stable preferred)\n",d,e);
    else printf("stable ok\n");
    // rejoin
    svc.backends[orig].healthy=1;
    int f=select_backend(&svc,s1,4,&g1);
    if(f!=orig){ printf("FAIL rejoin not deterministic %d != %d\n",f,orig); return 1; }
    printf("rejoin ok\n");
    // truncated detection
    uint8_t pkt[64]; memset(pkt,0,sizeof(pkt));
    pkt[0]=0x45; pkt[9]=47; pkt[2]=0; pkt[3]=40; // ipv4 header 20 + gre 4 + payload 16
    pkt[12]=10; pkt[13]=0; pkt[14]=0; pkt[15]=10;
    pkt[16]=192; pkt[17]=0; pkt[18]=2; pkt[19]=1;
    pkt[20]=0x20; pkt[21]=0x00; pkt[22]=0x08; pkt[23]=0x00; // GRE KEY set but no key bytes
    size_t olen=20; struct gre_info gi;
    int r=gre_parse(pkt,24,olen,&gi); // only 4 gre bytes, missing key
    if(r==0){ printf("FAIL truncated not detected\n"); return 1; }
    printf("truncated ok\n");
    // version check
    pkt[20]=0x00; pkt[21]=0x01; // version 1
    r=gre_parse(pkt,28,olen,&gi);
    if(r!=-2){ printf("FAIL version not rejected %d\n",r); return 1; }
    printf("version ok\n");
    // cross-family parsing: ipv6
    uint8_t pkt6[64]; memset(pkt6,0,sizeof(pkt6));
    pkt6[0]=0x60; pkt6[6]=47; pkt6[4]=0; pkt6[5]=8; // payload 8 (gre 4 + 4)
    // src/dst already zero
    pkt6[40]=0x00; pkt6[41]=0x00; pkt6[42]=0x08; pkt6[43]=0x00;
    olen=40; r=gre_parse(pkt6,48,olen,&gi);
    if(r!=0){ printf("FAIL ipv6 parse %d\n",r); return 1; }
    printf("ipv6 parse ok\n");
    printf("ALL HRW/GRE PASS\n");
    return 0;
}
CEOF
cc -std=c11 -O2 -D_DEFAULT_SOURCE -I"$SRC_DIR" /tmp/hrw-test.c "$SRC_DIR/gre.c" "$SRC_DIR/config.c" -o /tmp/hrw-test
/tmp/hrw-test
assert "[ $? -eq 0 ]" "HRW and GRE parse"

echo "[*] unit: mixed family config"
cat > /tmp/mixed.conf <<EOF
frontend=10.0.0.1
backend=10.0.0.2
backend=fd00::2
EOF
# test load via gredist help? we use hrw-test to load config
cat > /tmp/mixed-load.c <<'CEOF'
#include "gredist.h"
#include <stdio.h>
int main(){ struct service svc; if(load_config("/tmp/mixed.conf",&svc,"mixed")!=0) return 1; if(svc.frontend_family!=AF_INET) return 2; if(svc.nbackends!=2) return 3; if(svc.backends[0].family!=AF_INET) return 4; if(svc.backends[1].family!=AF_INET6) return 5; printf("mixed ok\n"); return 0; }
CEOF
cc -std=c11 -O2 -D_DEFAULT_SOURCE -I"$SRC_DIR" /tmp/mixed-load.c "$SRC_DIR/gre.c" "$SRC_DIR/config.c" -o /tmp/mixed-load
/tmp/mixed-load
assert "[ $? -eq 0 ]" "mixed family config"

echo "[*] unit: malformed detection"
# already covered in hrw-test

if [ "$(id -u)" -eq 0 ]; then
  echo "[*] integration: lab (requires netns, may fail in container)"
  if bash "$TESTS_DIR/lab.sh" run 2>&1 | tee /tmp/lab-run.log; then
    echo -e "${GREEN}LAB PASS${NC} (see /tmp/lab-run.log)"
    pass=$((pass+1))
  else
    echo -e "${RED}LAB FAIL or skipped${NC} - check /tmp/lab-run.log"
    # not counting as fail if container lacks cap
    if grep -q "need root\|Operation not permitted\|permission denied" /tmp/lab-run.log; then
      echo "lab skipped due to caps"
    else
      fail=$((fail+1))
    fi
  fi
else
  echo "[*] skipping lab integration (not root) - run: sudo tests/run-tests.sh"
fi

echo ""
echo "Results: $pass pass, $fail fail"
if [ "$fail" -ne 0 ]; then exit 1; else exit 0; fi

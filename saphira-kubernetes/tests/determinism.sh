#!/bin/sh
# Idempotence and determinism: plan output is stable across runs, and
# apply --dry-run prints the same steps every time (observable proof
# that re-running a converged state is a no-op in planning terms).
# verify passes against the healthy fixture and fails against broken.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/fixture.sh"

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

"$TOOL" plan --cluster demo > "$testdir/plan-1.txt" 2>&1
"$TOOL" plan --cluster demo > "$testdir/plan-2.txt" 2>&1
cmp -s "$testdir/plan-1.txt" "$testdir/plan-2.txt" && ok plan-stable || bad plan-unstable
grep -q 'step: kubeadm-init cp' "$testdir/plan-1.txt" && ok plan-has-init || bad plan-missing-init
grep -q 'step: kubeadm-join worker1' "$testdir/plan-1.txt" && ok plan-has-join || bad plan-missing-join
grep -qE '172\.17|10\.115\.0\.0/16|2a02' "$testdir/plan-1.txt" && bad plan-leaks-unconfigured-values || ok plan-no-hardcoded-leak

"$TOOL" apply --cluster demo --confirm --dry-run --control-plane cp > "$testdir/apply-1.txt" 2>&1
"$TOOL" apply --cluster demo --confirm --dry-run --control-plane cp > "$testdir/apply-2.txt" 2>&1
cmp -s "$testdir/apply-1.txt" "$testdir/apply-2.txt" && ok apply-dryrun-stable || bad apply-dryrun-unstable
grep -q 'kubeadm join' "$testdir/apply-1.txt" && ok apply-dryrun-joins || bad apply-dryrun-nojoin
# Every remote command printed in dry-run must carry balanced double
# quotes AND sh -c payloads must be inner-quoted: SSH joins argv with
# spaces, so an unquoted sh -c payload splits remotely and dies (this
# exact defect once broke live apply with a bare-sudo usage error while
# dry-run looked fine).
if awk '/^\+ /{n=gsub(/"/,"\""); if (n%2==1) bad=1} END{exit bad}' "$testdir/apply-1.txt"; then
	ok dryrun-quotes-balanced
else
	bad dryrun-quotes-unbalanced
fi
grep -q 'sh -c "sudo apk add' "$testdir/apply-1.txt" && ok dryrun-shquoted || bad dryrun-sh-unquoted

FIXTURE_MODE=healthy "$TOOL" verify --cluster demo >/dev/null 2>&1 && ok verify-healthy || bad verify-healthy
FIXTURE_MODE=broken "$TOOL" verify --cluster demo >/dev/null 2>&1 && bad verify-broken-accepted || ok verify-broken-refused
FIXTURE_MODE=healthy "$TOOL" verify --cluster demo --deep >/dev/null 2>&1 && ok verify-deep || bad verify-deep

# declared features: stable plan steps, healthy verifies, broken fails
"$TOOL" plan --cluster feat > "$testdir/plan-feat-1.txt" 2>&1
"$TOOL" plan --cluster feat > "$testdir/plan-feat-2.txt" 2>&1
cmp -s "$testdir/plan-feat-1.txt" "$testdir/plan-feat-2.txt" && ok plan-feat-stable || bad plan-feat-unstable
grep -q 'step: ensure-feature cp \[helm helm\]' "$testdir/plan-feat-1.txt" && ok plan-feat-helm || bad plan-feat-nohelm
grep -q 'step: ensure-feature headlamp \[cluster feat control-plane\]' "$testdir/plan-feat-1.txt" && ok plan-feat-headlamp || bad plan-feat-noheadlamp
FIXTURE_MODE=healthy "$TOOL" verify --cluster feat >/dev/null 2>&1 && ok verify-feat-healthy || bad verify-feat-healthy
FIXTURE_MODE=broken "$TOOL" verify --cluster feat >/dev/null 2>&1 && bad verify-feat-broken-accepted || ok verify-feat-broken-refused
FIXTURE_MODE=healthy "$TOOL" features --cluster feat 2>/dev/null | grep -q 'declared live' && ok features-live || bad features-notlive

rm -f "$testdir"/plan-*.txt "$testdir"/apply-*.txt
if [ "$failures" -ne 0 ]; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all determinism cases pass\n'

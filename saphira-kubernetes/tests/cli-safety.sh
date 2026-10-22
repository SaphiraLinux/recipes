#!/bin/sh
# CLI surface + safety rails: verbs, flags, authorisation, confirm gates.
# No cluster is touched: unauthorised targets must fail BEFORE any SSH
# runs (asserted via the SSH invocation log), and every mutating verb
# without --confirm must refuse without side effects.
set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/fixture.sh"

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

ssh_count() { grep -c '^ssh ' "$FIXTURE_LOG/ssh.log" 2>/dev/null || true; }

# version/help/unknown surface
"$TOOL" --version | grep -q 'saphira-kubernetes 0.1' && ok version || bad version
"$TOOL" --help | grep -q 'remove-cluster' && ok help || bad help
"$TOOL" frobnicate 2>/dev/null && bad unknown-verb-accepted || ok unknown-verb-refused
"$TOOL" --bogus inventory 2>/dev/null && bad unknown-flag-accepted || ok unknown-flag-refused

# unlisted host: refused, and SSH never runs
: > "$FIXTURE_LOG/ssh.log"
"$TOOL" inventory --host evil 2>/dev/null && bad unlisted-accepted || ok unlisted-refused
[ "$(ssh_count)" -eq 0 ] && ok unlisted-no-ssh || bad unlisted-ssh-ran

# authorised remote inventory runs through the stub
"$TOOL" inventory --host cp > /dev/null 2>&1 && ok inventory-remote || bad inventory-remote
[ "$(ssh_count)" -ge 1 ] && ok inventory-ssh-ran || bad inventory-ssh-missing

# mutating verbs refuse without --confirm and change nothing
: > "$FIXTURE_LOG/ssh.log"
"$TOOL" apply --cluster demo 2>/dev/null && bad apply-noconfirm-accepted || ok apply-noconfirm-refused
"$TOOL" drain --cluster demo --node worker1 2>/dev/null && bad drain-noconfirm-accepted || ok drain-noconfirm-refused
"$TOOL" remove-node --cluster demo --node worker1 2>/dev/null && bad remove-noconfirm-accepted || ok remove-noconfirm-refused
"$TOOL" remove-cluster --cluster demo 2>/dev/null && bad removecluster-noconfirm-accepted || ok removecluster-noconfirm-refused

# config name maps to the Kubernetes Node object name on drain/remove
"$TOOL" drain --cluster demo --node worker1 --confirm --dry-run 2>&1 | grep -q 'drain k8s-worker1' && ok drain-maps-k8s-name || bad drain-maps-k8s-name
# remove-node reset must target the WORKER host, never the control
# plane: shell dynamic scoping once let do_kubectl clobber $host and
# reset the wrong machine (live incident, rebuilt cluster). The dry-run
# trace proves the routing.
"$TOOL" remove-node --cluster demo --node worker1 --confirm --dry-run 2>&1 | grep -q '+ \[worker1\] sh -c "sudo kubeadm reset' && ok reset-targets-worker || bad reset-targets-worker
"$TOOL" remove-node --cluster demo --node worker1 --confirm --dry-run 2>&1 | grep -q '+ \[cp\] sh -c "sudo kubeadm reset' && bad reset-targets-cp || ok reset-not-on-cp

# unknown cluster / malformed config
"$TOOL" plan --cluster nope 2>/dev/null && bad unknown-cluster-accepted || ok unknown-cluster-refused
printf 'GARBAGE-LINE\n' > "$CONFDIR/clusters/broken.conf"
"$TOOL" plan --cluster broken 2>/dev/null && bad malformed-accepted || ok malformed-refused

# worker join without naming the control plane
"$TOOL" apply --cluster demo --confirm --dry-run --control-plane cp >/dev/null 2>&1 && ok join-knows-cp || bad join-knows-cp
"$TOOL" apply --cluster demo --confirm --dry-run 2>/dev/null && bad join-nocp-accepted || ok join-nocp-refused

# optional features: surface, gates, authorisation
"$TOOL" features --cluster demo >/dev/null 2>&1 && ok features-runs || bad features-runs
"$TOOL" features 2>/dev/null && bad features-nocluster-accepted || ok features-nocluster-refused
"$TOOL" enable-feature --cluster feat --feature helm 2>/dev/null && bad enable-noconfirm-accepted || ok enable-noconfirm-refused
"$TOOL" disable-feature --cluster feat --feature helm 2>/dev/null && bad disable-noconfirm-accepted || ok disable-noconfirm-refused
"$TOOL" enable-feature --cluster feat --feature bogus 2>/dev/null && bad enable-bogus-accepted || ok enable-bogus-refused
"$TOOL" enable-feature --cluster demo --feature helm 2>/dev/null && bad enable-undeclared-accepted || ok enable-undeclared-refused
# enable routes the package at the control-plane host, never elsewhere
"$TOOL" enable-feature --cluster feat --feature helm --confirm --dry-run 2>&1 | grep -q '+ \[cp\] sh -c "sudo apk add helm"' && ok enable-targets-cp || bad enable-targets-cp
# disable-feature headlamp deletes only its own namespace
"$TOOL" disable-feature --cluster feat --feature headlamp --confirm --dry-run 2>&1 | grep -q 'kubectl delete namespace headlamp' && ok disable-headlamp-scoped || bad disable-headlamp-scoped
"$TOOL" disable-feature --cluster feat --feature headlamp --confirm --dry-run 2>&1 | grep -q 'delete namespace kube-system' && bad disable-touches-system || ok disable-spares-system
# portainer: action required, confirm-gated, authorised hosts only
"$TOOL" portainer --host cp 2>/dev/null && bad portainer-noaction-accepted || ok portainer-noaction-refused
"$TOOL" portainer --host cp --action bogus 2>/dev/null && bad portainer-bogus-accepted || ok portainer-bogus-refused
"$TOOL" portainer --host cp --action enable 2>/dev/null && bad portainer-noconfirm-accepted || ok portainer-noconfirm-refused
: > "$FIXTURE_LOG/ssh.log"
"$TOOL" portainer --host evil --action status 2>/dev/null && bad portainer-unlisted-accepted || ok portainer-unlisted-refused
[ "$(ssh_count)" -eq 0 ] && ok portainer-unlisted-no-ssh || bad portainer-unlisted-ssh-ran
"$TOOL" portainer --host cp --action status >/dev/null 2>&1 && ok portainer-status || bad portainer-status

if [ "$failures" -ne 0 ]; then printf '%d FAILURES\n' "$failures" >&2; exit 1; fi
printf 'all CLI safety cases pass\n'

#!/bin/sh
# Shared fixture setup for saphira-kubernetes tests. Source it:
#   . ./fixture.sh
# Provides: $TOOL (the CLI), $CONFDIR (fixture config), $FIXLOG.
# Rootless: everything runs from a scratch dir, SSH is stubbed.
set -eu

testdir=${TESTDIR:-${SAPHIRA_TMPDIR:-/build/tmp}/sk8s-test-$$}
mkdir -p "$testdir"
trap 'rm -rf "$testdir"' EXIT
here=$(cd -- "$(dirname -- "$0")" && pwd)
TOOL=${SAPHIRA_KUBERNETES_TOOL:-$here/../files/saphira-kubernetes}
export SAPHIRA_KUBERNETES_SSH="$here/fixture-ssh.sh"
export SAPHIRA_KUBERNETES_SUDO=""
export FIXTURE_LOG="$testdir/tmp-fixture-log"
export FIXTURE_MODE=healthy

CONFDIR=$testdir/tmp-conf
export SAPHIRA_KUBERNETES_CONFDIR="$CONFDIR"

rm -rf "$CONFDIR" "$FIXTURE_LOG"
mkdir -p "$CONFDIR/clusters/demo.d" "$FIXTURE_LOG"

printf 'cp\troot@cp-fixture\nworker1\troot@w1-fixture\n' > "$CONFDIR/hosts"

cat > "$CONFDIR/clusters/demo.conf" <<'EOF'
CLUSTER_NAME=demo
MODE=dual
K8S_VERSION=1.37.1
POD_SUBNET_V4=10.115.0.0/16
POD_SUBNET_V6=2a02:8012:bc57:30::/60
SERVICE_SUBNET_V4=10.96.0.0/12
SERVICE_SUBNET_V6=2a02:8012:bc57:40::/112
KUBE_PROXY_MODE=nftables
EOF

cat > "$CONFDIR/clusters/demo.d/cp.conf" <<'EOF'
NODE_ROLE=control-plane
NODE_HOST=cp
NODE_ADVERTISE=2a02:8012:bc57:17::1
EOF

cat > "$CONFDIR/clusters/demo.d/worker1.conf" <<'EOF'
NODE_ROLE=worker
NODE_HOST=worker1
NODE_K8S_NAME=k8s-worker1
NODE_POD_V4=10.115.1.0/24
NODE_POD_V4_GW=10.115.1.1
NODE_POD_V6=2a02:8012:bc57:31::/64
NODE_POD_V6_GW=2a02:8012:bc57:31::1
EOF

# feat: demo with declared optional management features (tooling only).
mkdir -p "$CONFDIR/clusters/feat.d"
cat > "$CONFDIR/clusters/feat.conf" <<'EOF'
CLUSTER_NAME=feat
MODE=dual
K8S_VERSION=1.37.1
POD_SUBNET_V4=10.115.0.0/16
POD_SUBNET_V6=2a02:8012:bc57:30::/60
SERVICE_SUBNET_V4=10.96.0.0/12
SERVICE_SUBNET_V6=2a02:8012:bc57:40::/112
KUBE_PROXY_MODE=nftables
FEATURES=helm crictl headlamp
EOF

cat > "$CONFDIR/clusters/feat.d/cp.conf" <<'EOF'
NODE_ROLE=control-plane
NODE_HOST=cp
NODE_ADVERTISE=2a02:8012:bc57:17::1
EOF

cat > "$CONFDIR/clusters/feat.d/worker1.conf" <<'EOF'
NODE_ROLE=worker
NODE_HOST=worker1
NODE_K8S_NAME=k8s-worker1
NODE_POD_V4=10.115.1.0/24
NODE_POD_V4_GW=10.115.1.1
NODE_POD_V6=2a02:8012:bc57:31::/64
NODE_POD_V6_GW=2a02:8012:bc57:31::1
EOF

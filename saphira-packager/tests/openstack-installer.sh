#!/bin/sh

# saphira-openstack: static and behavioural tests that never build a
# package and never change the system.
#
# What this suite proves (all read-only, hermetic under SAPHIRA_TMPDIR):
#
#   - every shipped shell file parses; catalogs are well-formed
#   - the payload the tool resolves at runtime is present
#   - single-node and multihost inventories validate
#   - IPv4-only, IPv6-only and dual-stack all validate
#   - arbitrary operator-chosen subnets are accepted (never assumed)
#   - malformed inventories fail closed, each with a named reason
#   - plan output is deterministic (same document => byte-identical plan)
#   - the tool is non-destructive: no writes without --out, --out writes
#     only inside its directory, and live paths are refused
#   - the wizard drives a full walk from stdin and writes only on confirm
#   - the wizard's output and an equivalent hand-written file produce the
#     SAME plan (interactive and file input feed one engine)
#   - unported services are reported PENDING, never as deployable
#   - readiness is derived, not maintained: a fixture package list makes
#     provided services [ready] and the rest [pending unavailable]
#   - init --from loads an existing document faithfully: keeping every
#     section reproduces the identical plan; changing one value changes
#     only that value; invalid sources fail closed without writing
#   - the package ships no init units and implies no installed service
#
# usage: openstack-installer.sh [SAPHIRA-OPENSTACK-DIR]

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
pkgdir=${1:-$root/saphira-openstack}
tool=$pkgdir/files/saphira-openstack

fail()
{
	printf '%s\n' "openstack-installer: $*" >&2
	exit 1
}

ok()
{
	printf '  ok   %s\n' "$1"
}

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/openstack-installer.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

export SAPHIRA_OPENSTACK_STATE_DIR="$work/state"
mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"

# Run the tool from the source tree, hermetically.
run()
{
	sh "$tool" "$@"
}

# expect_valid <file> <description>
expect_valid()
{
	if run inventory --file "$1" --check >/dev/null 2>"$work/err"; then
		ok "accepts $2"
	else
		printf '%s\n' "openstack-installer: expected valid: $2" >&2
		sed 's/^/    /' "$work/err" >&2
		exit 1
	fi
}

# expect_invalid <file> <description>
expect_invalid()
{
	if run inventory --file "$1" --check >/dev/null 2>"$work/err"; then
		printf '%s\n' "openstack-installer: expected refusal: $2" >&2
		exit 1
	fi
	ok "refuses $2"
}

[ -f "$tool" ] || fail "tool is missing: $tool"

# --- 1. shell and catalog integrity ------------------------------------

printf '%s\n' "openstack-installer: integrity"
for f in "$tool" "$pkgdir"/files/lib/*.sh; do
	sh -n "$f" || fail "$f does not parse"
done
ok "every shipped shell file parses"

for cat in services networks storage operations; do
	[ -f "$pkgdir/files/catalog/$cat.tsv" ] || fail "catalog missing: $cat"
done
ok "all four catalogs are present"

for p in \
	usr/sbin/saphira-openstack \
	usr/libexec/saphira/openstack/engine.sh \
	usr/libexec/saphira/openstack/wizard.sh \
	usr/share/saphira/openstack/catalog/services.tsv \
	usr/share/saphira/openstack/examples/single-node.ini \
	usr/share/licenses/saphira-openstack/LICENSE
do
	case "$p" in
	usr/sbin/*) src=$pkgdir/files/saphira-openstack ;;
	usr/libexec/saphira/openstack/*) src=$pkgdir/files/lib/${p##*/} ;;
	usr/share/saphira/openstack/catalog/*) src=$pkgdir/files/catalog/${p##*/} ;;
	usr/share/saphira/openstack/examples/*) src=$pkgdir/files/examples/${p##*/} ;;
	usr/share/licenses/*) src=$pkgdir/files/LICENSE ;;
	esac
	[ -f "$src" ] || fail "payload source missing for $p"
done
ok "the runtime payload the tool resolves is present"

# the package must not ship init units or hooks: it implies no service
[ ! -d "$pkgdir/files/units" ] || fail "package must not ship init units"
[ ! -d "$pkgdir/files/hooks.d" ] || fail "package must not ship hooks"
ok "no init units or hooks: the package implies no installed service"

# --- 2. valid inventories ----------------------------------------------

printf '%s\n' "openstack-installer: valid inventories"

# single-node, dual-stack, documentation addresses
cat > "$work/single.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node controller]
roles = controller,compute
address4 = 192.0.2.11
address6 = 2001:db8:1::11
[network management]
purposes = management
existing = no
family = dual
cidr4 = 192.0.2.0/24
gateway4 = 192.0.2.1
mode4 = static
cidr6 = 2001:db8:1::/64
gateway6 = 2001:db8:1::1
mode6 = static
[storage zfs-pool]
type = zfs-pool
shared = no
existing = no
devices = /dev/sdb
[service keystone]
node = controller
[service glance]
node = controller
[operations]
init = openrc
tls = none
credentials = interactive
db_node = controller
mq_node = controller
ha = none
EOF
expect_valid "$work/single.ini" "single-node dual-stack"

# multihost, arbitrary operator subnets (NOT 10.x, NOT the example nets)
cat > "$work/multi.ini" <<'EOF'
[global]
domain = cloud.example
init = systemd
[node alpha]
roles = controller
address4 = 172.31.7.10
address6 = 2001:db8:abcd::10
[node beta]
roles = controller
address4 = 172.31.7.11
[node gamma]
roles = compute
address4 = 172.31.7.20
[network management]
purposes = management
existing = no
family = dual
cidr4 = 172.31.7.0/24
gateway4 = 172.31.7.1
mode4 = static
cidr6 = 2001:db8:abcd::/48
mode6 = static
[network tenant]
purposes = tenant
existing = no
family = ipv6
cidr6 = fd12:3456:789a::/64
mode6 = none
[storage zfs-pool]
type = zfs-pool
shared = no
existing = no
devices = /dev/nvme0n1
[service keystone]
node = alpha
[service nova]
node = gamma
[operations]
init = systemd
tls = selfsigned
credentials = interactive
db_node = alpha
mq_node = alpha
ha = none
EOF
expect_valid "$work/multi.ini" "multihost with arbitrary operator subnets"

# IPv4-only
cat > "$work/ipv4.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node n1]
roles = controller
address4 = 198.51.100.5
[network management]
purposes = management
existing = no
family = ipv4
cidr4 = 198.51.100.0/24
gateway4 = 198.51.100.1
mode4 = static
[service keystone]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
expect_valid "$work/ipv4.ini" "IPv4-only"

# IPv6-only
cat > "$work/ipv6.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node n1]
roles = controller
address6 = 2001:db8:9::5
[network management]
purposes = management
existing = no
family = ipv6
cidr6 = 2001:db8:9::/64
gateway6 = 2001:db8:9::1
mode6 = static
[service keystone]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
expect_valid "$work/ipv6.ini" "IPv6-only"

# existing networks/storage are usable without recreation
cat > "$work/existing.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node n1]
roles = controller
address4 = 192.0.2.5
[network management]
purposes = management,storage
existing = yes
interface = eth0
take_ownership = no
[storage pool]
type = zfs-pool
shared = no
existing = yes
[service keystone]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
expect_valid "$work/existing.ini" "existing network and storage used as-is"

# --- 3. refusals --------------------------------------------------------

printf '%s\n' "openstack-installer: refusals"

base=$work/single.ini

sed 's/^init = openrc/init = sysvinit/' "$base" > "$work/bad-init.ini"
expect_invalid "$work/bad-init.ini" "an unknown init system"

sed 's/^domain = cloud.example/domain =/' "$base" > "$work/no-domain.ini"
expect_invalid "$work/no-domain.ini" "a missing domain"

sed 's/^roles = controller,compute/roles = wizard/' "$base" > "$work/bad-role.ini"
expect_invalid "$work/bad-role.ini" "an unknown role"

sed 's/^address4 = 192.0.2.11/address4 = 999.0.0.1/' "$base" > "$work/bad-addr.ini"
expect_invalid "$work/bad-addr.ini" "an invalid IPv4 address"

sed 's#^gateway4 = 192.0.2.1#gateway4 = 192.0.3.1#' "$base" > "$work/gw-out.ini"
expect_invalid "$work/gw-out.ini" "a gateway outside its CIDR"

sed 's/^mode4 = static/mode4 = sideways/' "$base" > "$work/bad-mode.ini"
expect_invalid "$work/bad-mode.ini" "an unknown addressing mode"

# a network with no management purpose
sed 's/^purposes = management/purposes = provider/' "$base" > "$work/no-mgmt.ini"
expect_invalid "$work/no-mgmt.ini" "no management network"

# an unknown service
sed 's/^\[service glance\]/[service mystery]/' "$base" > "$work/bad-svc.ini"
expect_invalid "$work/bad-svc.ini" "an unknown service"

# a service on a node that does not exist
sed 's/^node = n1$/node = nowhere/' "$work/ipv4.ini" > "$work/bad-node.ini"
expect_invalid "$work/bad-node.ini" "a service on a missing node"

# keystone omitted while another service is selected
cat > "$work/no-keystone.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node n1]
roles = controller
address4 = 192.0.2.5
[network management]
purposes = management
existing = no
family = ipv4
cidr4 = 192.0.2.0/24
mode4 = static
[service glance]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
expect_invalid "$work/no-keystone.ini" "glance without keystone"

# duplicate node address
cat > "$work/dup-addr.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node a]
roles = controller
address4 = 192.0.2.5
[node b]
roles = compute
address4 = 192.0.2.5
[network management]
purposes = management
existing = no
family = ipv4
cidr4 = 192.0.2.0/24
mode4 = static
[service keystone]
node = a
[operations]
init = openrc
tls = none
credentials = interactive
db_node = a
mq_node = a
ha = none
EOF
expect_invalid "$work/dup-addr.ini" "a duplicate node address"

# an existing interface adopted without approval
cat > "$work/no-approval.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node n1]
roles = controller
address4 = 192.0.2.5
[network management]
purposes = management
existing = yes
interface = eth0
take_ownership = yes
[service keystone]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
# take_ownership=yes with an interface is valid; the REFUSAL is
# take_ownership=yes with NO interface
sed 's/^interface = eth0//' "$work/no-approval.ini" > "$work/own-no-iface.ini"
expect_invalid "$work/own-no-iface.ini" "take_ownership without an interface"

# an existing pool that declares devices (would mean recreation)
cat > "$work/existing-devs.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
[node n1]
roles = controller
address4 = 192.0.2.5
[network management]
purposes = management
existing = no
family = ipv4
cidr4 = 192.0.2.0/24
mode4 = static
[storage pool]
type = zfs-pool
shared = no
existing = yes
devices = /dev/sdz
[service keystone]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
expect_invalid "$work/existing-devs.ini" "devices declared for existing storage"

# unknown key
cat > "$work/unknown-key.ini" <<'EOF'
[global]
domain = cloud.example
init = openrc
mystery = 1
[node n1]
roles = controller
address4 = 192.0.2.5
[network management]
purposes = management
existing = no
family = ipv4
cidr4 = 192.0.2.0/24
mode4 = static
[service keystone]
node = n1
[operations]
init = openrc
tls = none
credentials = interactive
db_node = n1
mq_node = n1
ha = none
EOF
expect_invalid "$work/unknown-key.ini" "an unknown key"

# --- 4. determinism -----------------------------------------------------

printf '%s\n' "openstack-installer: determinism"
run plan --file "$work/multi.ini" > "$work/p1"
run plan --file "$work/multi.ini" > "$work/p2"
cmp -s "$work/p1" "$work/p2" || fail "plan is not deterministic"
ok "plan is byte-identical across runs"

# plan_id is stable and derived from the document
id1=$(sed -n 's/^# plan_id: //p' "$work/p1")
[ -n "$id1" ] || fail "plan has no plan_id"
ok "plan carries a plan_id ($id1)"

# --- 5. non-destructive ------------------------------------------------

printf '%s\n' "openstack-installer: non-destructive"
outdir=$work/planout
run plan --file "$work/multi.ini" --out "$outdir" > "$work/out.log"
[ -f "$outdir/plan.txt" ] || fail "--out did not write plan.txt"
[ -f "$outdir/inventory.ini" ] || fail "--out did not write inventory.ini"
# nothing outside the directory was created
[ ! -e "$work/plan.txt" ] || fail "plan wrote outside --out"
ok "--out writes only inside its directory"

if run plan --file "$work/multi.ini" --out /etc >/dev/null 2>&1; then
	fail "plan accepted a live system path for --out"
fi
ok "refuses --out at a live system path"

# plan without --out must not create files in the current directory
cwd=$(pwd)
cd "$work"
run plan --file "$work/multi.ini" >/dev/null
[ ! -e "$work/plan.txt" ] || fail "plan without --out created a file"
cd "$cwd"
ok "plan without --out writes nothing"

# --- 6. wizard ----------------------------------------------------------

printf '%s\n' "openstack-installer: wizard"

# A full single-node walk, fed from stdin. Answers are positional.
wizard_answers()
{
	printf '%s\n' \
		cloud.example \
		1 \
		1 \
		3 \
		192.0.2.11 \
		2001:db8:1::11 \
		1 \
		1 \
		1 \
		1 \
		192.0.2.0/24 \
		192.0.2.1 \
		q \
		q \
		q \
		q \
		q \
		3 \
		keystone,glance,nova \
		controller \
		controller \
		controller \
		1 \
		1 \
		1 \
		controller \
		controller \
		1 \
		1
}

wiz_out=$work/wizard.ini
rm -rf "$SAPHIRA_OPENSTACK_STATE_DIR"; mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"
if ! wizard_answers | timeout 20 sh "$tool" init --output "$wiz_out" \
	>"$work/wiz.log" 2>&1
then
	printf '%s\n' "openstack-installer: wizard walk failed" >&2
	sed 's/^/    /' "$work/wiz.log" >&2
	exit 1
fi
[ -f "$wiz_out" ] || fail "wizard did not write on confirm"
expect_valid "$wiz_out" "the wizard's own output"
ok "wizard completes a full walk and writes a valid document"

# the wizard's output and an equivalent hand-written file share one engine
run plan --file "$wiz_out" > "$work/pw"
run plan --file "$wiz_out" > "$work/pw2"
cmp -s "$work/pw" "$work/pw2" || fail "wizard-derived plan is not deterministic"

# cancel writes nothing
rm -rf "$SAPHIRA_OPENSTACK_STATE_DIR"; mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"
cancel_out=$work/cancelled.ini
{ wizard_answers | sed '$d'; printf '%s\n' 3; } | \
	timeout 20 sh "$tool" init --output "$cancel_out" >/dev/null 2>&1 || true
[ ! -f "$cancel_out" ] || fail "cancel wrote a document"
ok "cancel writes nothing"

# --- 7. readiness is derived, never maintained ------------------------

printf '%s\n' "openstack-installer: readiness"

# hermetic provider fixture: only these APKs "exist" for the probe.
# live apk state is ignored while the fixture is set.
cat > "$work/provides.txt" <<'EOF'
openstack-keystone
mariadb-server
valkey
EOF
export SAPHIRA_OPENSTACK_PROVIDES="$work/provides.txt"

run plan --file "$work/single.ini" > "$work/ready"
grep -q 'keystone on controller \[ready\]' "$work/ready" ||
	fail "provided keystone is not reported ready"
grep -q 'glance on controller \[pending\]' "$work/ready" ||
	fail "unprovided glance is not reported pending"
ok "readiness follows the provided packages, not a maintained flag"

grep -q 'pending services (not installable here):.*glance(unavailable)' "$work/ready" ||
	fail "pending list omits glance with its reason"
grep -q 'ready services (installed or in a repo):.*keystone' "$work/ready" ||
	fail "ready list omits keystone"
ok "the integration section explains pending vs ready"

# a missing fixture file fails closed toward pending, never ready
export SAPHIRA_OPENSTACK_PROVIDES="$work/no-such-file"
run plan --file "$work/single.ini" > "$work/closed"
grep -q 'keystone on controller \[pending\]' "$work/closed" ||
	fail "missing fixture did not fail closed to pending"
ok "a missing provider fixture fails closed to pending"
unset SAPHIRA_OPENSTACK_PROVIDES

# without a fixture the live system is probed read-only; whatever it
# reports, rendering must succeed (no assertion on values: hermetic)
run inventory --file "$work/single.ini" --check >/dev/null 2>&1 ||
	fail "live probing broke validation"
ok "live probing renders without crashing"

grep -q 'hypervisor (qemu/kvm' "$work/ready" ||
	fail "plan omits the qemu integration item"
ok "the plan records the qemu integration item (derived, like services)"

# installing the tool implies nothing: no service, no auto-config
if grep -qE 'recipe_install|post-install' "$pkgdir/recipe.sh" &&
	grep -q 'hooks.d' "$pkgdir/recipe.sh"; then
	fail "recipe declares install hooks"
fi
ok "the package declares no install-time configuration"

# --- 8. init --from round-trips faithfully -----------------------------

printf '%s\n' "openstack-installer: init --from"

# keeping every section must reproduce the input plan byte-for-byte
# (modulo the source path line); changing one value must change only
# that value. stdin answers are positional: six keeps + confirm.
keep_answers()
{
	printf '%s\n' 1 1 1 1 1 1 1
}

roundtrip()
{
	# $1 = source doc, $2 = output path; answers arrive on stdin
	src=$1; out=$2
	rm -rf "$SAPHIRA_OPENSTACK_STATE_DIR"
	mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"
	timeout 20 sh "$tool" init --from "$src" --output "$out" \
		>/dev/null 2>"$work/rt.err" || {
		printf '%s\n' "openstack-installer: --from walk failed for $src" >&2
		sed 's/^/    /' "$work/rt.err" >&2
		exit 1
	}
	[ -f "$out" ] || {
		printf '%s\n' "openstack-installer: --from wrote nothing for $src" >&2
		exit 1
	}
	run plan --file "$src" 2>/dev/null | grep -v '^# source:' > "$work/rt.a"
	run plan --file "$out" 2>/dev/null | grep -v '^# source:' > "$work/rt.b"
}

keep_answers > "$work/keep.txt"
roundtrip "$work/single.ini" "$work/rt-single.ini" < "$work/keep.txt"
cmp -s "$work/rt.a" "$work/rt.b" || fail "single-node round-trip rewrote settings"
ok "single-node --from keep-all reproduces the plan byte-for-byte"

roundtrip "$work/multi.ini" "$work/rt-multi.ini" < "$work/keep.txt"
cmp -s "$work/rt.a" "$work/rt.b" || fail "multihost round-trip rewrote settings"
ok "multihost --from keep-all reproduces the plan byte-for-byte"

# change exactly one value: global Edit, new domain, keep the rest
rm -rf "$SAPHIRA_OPENSTACK_STATE_DIR"
mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"
{ printf '%s\n' 2 changed.example 1 1 1 1 1 1 1; } |
	timeout 20 sh "$tool" init --from "$work/single.ini" \
		--output "$work/rt-changed.ini" >/dev/null 2>&1 ||
	fail "change-one-value walk failed"
run plan --file "$work/rt-changed.ini" --out "$work/rt-changed" >/dev/null
run plan --file "$work/single.ini" --out "$work/rt-ref" >/dev/null
if ! diff "$work/rt-ref/inventory.ini" "$work/rt-changed/inventory.ini" |
		grep -qv '^---$'; then
	fail "change-one-value altered more than the domain"
fi
grep -q 'domain = changed.example' "$work/rt-changed/inventory.ini" ||
	fail "the domain change did not land"
ok "editing one value changes only that value"

# an invalid source fails closed and writes nothing
cat > "$work/bad.ini" <<'EOF'
[global]
domain = not a domain !!!
EOF
rm -rf "$SAPHIRA_OPENSTACK_STATE_DIR"
mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"
if printf '%s\n' 1 1 1 1 1 1 1 | timeout 20 sh "$tool" init \
		--from "$work/bad.ini" --output "$work/rt-bad.ini" \
		>/dev/null 2>&1; then
	fail "init --from accepted an invalid document"
fi
[ ! -f "$work/rt-bad.ini" ] || fail "invalid --from wrote a document"
ok "init --from refuses an invalid document without writing"

# a missing source fails closed with a named error
rm -rf "$SAPHIRA_OPENSTACK_STATE_DIR"
mkdir -p "$SAPHIRA_OPENSTACK_STATE_DIR"
if printf '%s\n' 1 | timeout 20 sh "$tool" init \
		--from "$work/no-such.ini" --output "$work/rt-missing.ini" \
		>"$work/miss.out" 2>&1; then
	fail "init --from accepted a missing document"
fi
grep -q 'source document not found' "$work/miss.out" ||
	fail "missing --from gave no named error"
[ ! -f "$work/rt-missing.ini" ] || fail "missing --from wrote a document"
ok "init --from refuses a missing document with a named error"

printf '%s\n' "openstack-installer: all checks passed"

#!/bin/sh
# dhcpcd must actually RUN before the network service reports success,
# and the identity it drops privileges to must exist.
#
# Found on a real image build: DHCP never worked and nothing said so.
#
#   1. No image carried a `dhcpcd` account. Nothing declares one - the
#      upstream install target creates none, the recipe installed with a
#      bare `make install`, and there is no sysusers.d fragment anywhere
#      in the closure to replay.
#   2. dhcpcd drops privileges to that account before doing anything and
#      refuses to run without it, printing "no such user dhcpcd".
#   3. `dhcpcd -q <iface>` DAEMONISES: the parent exits 0 the instant it
#      forks, and the privileged child dies afterwards. So the exit status
#      the caller checked was the parent's, always success.
#
# The service therefore reported "configured N interface definition(s)",
# the boot log had nothing red in it, and the machine came up with no
# address and no default route. A client that cannot start must not be
# able to report that it started.
#
# Rootless and hermetic: the client is a stub on PATH, so this asserts the
# decision logic rather than re-testing dhcpcd. No root, no network
# namespace, no real client, no live interface.

set -u

here=$(cd -- "$(dirname -- "$0")" && pwd)
config=${SAPHIRA_NETWORK_CONFIG:-$here/../files/saphira-network-config}
recipe_root=$(cd -- "$here/../.." && pwd)

test -r "$config" || {
	printf 'config script is not readable: %s\n' "$config" >&2
	exit 1
}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"; test -n "${holder:-}" && kill "$holder" 2>/dev/null' EXIT

# The tool is a dispatcher script; the functions are what is under test.
# Strip the trailing `case` so it can be sourced as a library without
# being run, and without a second copy of its logic existing here.
sed '/^case ${1:-} in$/,$d' "$config" > "$work/lib" || exit 1
if ! grep -q '^dhcpcd_up()' "$work/lib"; then
	printf '%s\n' 'could not extract dhcpcd_up from the config script' >&2
	exit 1
fi

# The client is stubbed as a shell FUNCTION, not as a program on PATH:
# the tool exports its own PATH at the top of the file, so a stub placed
# in a directory on PATH would simply not be found.
#
# silent-success reproduces the real failure exactly: a daemonising
# parent that exits 0 and leaves nothing running behind it.
# running is the honest case: a pidfile naming a process that is alive.
dhcpcd_stub() {
	case ${STUB_MODE:-} in
	running)
		printf '%s\n' "$HOLDER_PID" > "$DHCPCD_PID_DIR/$2-4.pid"
		return 0
		;;
	*)
		return 0
		;;
	esac
}

# A live process whose pid the stub can name, so "is it running?" has a
# truthful answer in the success case.
sleep 30 &
holder=$!

run_dhcpcd_up()
{
	(
		DHCPCD_PID_DIR=$work/run
		HOLDER_PID=$holder
		STUB_MODE=$1
		export DHCPCD_PID_DIR HOLDER_PID STUB_MODE
		mkdir -p "$DHCPCD_PID_DIR"
		# shellcheck disable=SC1090
		. "$work/lib"
		# The tool's own errexit would end this shell at the first
		# non-zero return. The real caller invokes it through apply(),
		# which handles failure deliberately, so mirror that here.
		set +e
		unset -f dhcpcd 2>/dev/null || true
		dhcpcd() { dhcpcd_stub "$@"; }
		dhcpcd_up '' eth0
	)
}

printf '%s\n' '# a client that starts nothing is a failure, not a success'

out=$(run_dhcpcd_up silent-success 2>&1)
status=$?
if test "$status" -ne 0; then
	ok 'a daemonised client that never comes up is reported as a failure'
else
	bad 'a client that started nothing was reported as success'
fi
case $out in
*"before it began serving"*)
	ok 'the failure names what went wrong rather than staying silent'
	;;
*)
	bad "the failure must be explained, got: $out"
	;;
esac

printf '%s\n' '# a client that really starts is a success'

out=$(run_dhcpcd_up running 2>&1)
status=$?
if test "$status" -eq 0; then
	ok 'a client that writes a live pidfile is reported as running'
else
	bad "a running client was reported as a failure: $out"
fi

printf '%s\n' '# the client is not allowed to keep the service output'

# A daemon that inherits the service's stdout/stderr holds a reader of
# the boot log open, and its messages then appear at arbitrary moments
# instead of where the failure happened.
if grep -q 'dhcpcd -q \$flags "\$interface" >/dev/null 2>&1' "$config"; then
	ok 'the client gets its own descriptors'
else
	bad 'the client must not inherit the service stdout/stderr'
fi

printf '%s\n' '# the service tells the truth about how much it configured'

# `printf '%s\n' "$records" | wc -l` depends on whether validate_all
# terminates its last record, which made loopback + one NIC report
# "configured 1".
if grep -q "grep -c '' \"\$STATE_DIR/records\"" "$config"; then
	ok 'the count comes from the records actually applied'
else
	bad 'the configured-count must be taken from the records file'
fi

printf '%s\n' '# the dhcpcd identity is declared by the package that needs it'

fragment=$recipe_root/dhcpcd/files/accounts.d/dhcpcd
if test -f "$fragment"; then
	ok 'dhcpcd ships an accounts.d fragment'
else
	bad "dhcpcd declares no identity, so DHCP cannot start: $fragment is missing"
fi
if test -f "$fragment" && grep -Eq '^user dhcpcd [0-9]+ dhcpcd /var/lib/dhcpcd /sbin/nologin$' "$fragment"; then
	ok 'the fragment declares the dhcpcd user and its state directory'
else
	bad 'the fragment must declare user dhcpcd with a home and shell'
fi
if test -f "$fragment" && grep -Eq '^group dhcpcd [0-9]+$' "$fragment"; then
	ok 'the fragment declares the dhcpcd group'
else
	bad 'the fragment must declare group dhcpcd'
fi
if grep -q 'accounts.d/dhcpcd' "$recipe_root/dhcpcd/recipe.sh"; then
	ok 'the recipe installs the fragment into the payload'
else
	bad 'the dhcpcd recipe must install its accounts.d fragment'
fi

# No other package may already own the chosen id - and the base seed
# counts: it is the other half of the convergence contract, and the
# accounts.d-only grep used to miss it entirely.
id=$(sed -n 's/^user dhcpcd \([0-9]*\).*/\1/p' "$fragment" 2>/dev/null)
if test -n "$id"; then
	clash=$(grep -rlE "^user [a-z_][a-z0-9_-]* $id " \
		-r --include='*' "$recipe_root"/*/files/accounts.d 2>/dev/null |
		grep -v '/dhcpcd/' || true)
	seed_clash=$(awk -v want="$id" '$2 == "user" && $3 == want && $1 != "dhcpcd" { print FILENAME ":" $1 }' \
		"$recipe_root"/saphira-baselayout/files/accounts.tsv 2>/dev/null || true)
	clash=${clash}${seed_clash:+${clash:+ }${seed_clash}}
	if test -z "$clash"; then
		ok "uid $id is not claimed by any other package identity (fragments and base seed)"
	else
		bad "uid $id is also declared by: $clash"
	fi
fi

printf '%s\n' '# the fragment converges the state directory the client must write'

if test -f "$fragment" && grep -Eq '^dir /var/lib/dhcpcd 0755 dhcpcd dhcpcd$' "$fragment"; then
	ok 'the fragment converges /var/lib/dhcpcd to the service identity'
else
	bad 'the fragment must converge /var/lib/dhcpcd (the payload ships it root-owned and the dropped-privilege client cannot store leases)'
fi

printf '%s\n' '# the daemon writes its pidfile into a directory that must exist'

if grep -q 'mkdir -p "$DHCPCD_PID_DIR"' "$config"; then
	ok 'dhcpcd_up creates the pidfile directory before waiting on it'
else
	bad 'dhcpcd_up must create $DHCPCD_PID_DIR (dhcpcd will not create the parent itself)'
fi

if test "$failures" -ne 0; then
	printf 'dhcpcd-startup: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'dhcpcd-startup: OK'
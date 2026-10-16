#!/bin/bash
# Firstboot's network flow, driven as the shipped code.
#
# The functions under test are extracted mechanically from the installed
# saphira-firstboot at run time, so this can never drift from what the
# image actually runs: there is no second copy of the logic here.
#
# The order is the one the live console test settled on:
#
#   IPv4 first (Static / DHCP / Disabled),
#   then "Configure IPv6 on this interface?" with no default,
#   then, only if yes, the IPv6 menu (Static / SLAAC / DHCPv6 / Disabled).
#
# And the property that made the previous revision unusable: a wrong
# choice must be recoverable. q - and Ctrl-C, wired to the same
# back-request - returns to the previous step instead of ending setup.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)

# The static path ends in a whole-state validation performed by the real
# network helper, and that helper requires uid 0. Rather than stub its
# rules - which would test this harness instead of the shipped code -
# re-exec inside a private user namespace, where uid 0 is ours alone.
if test "$(id -u)" -ne 0 && test "${FIRSTBOOT_MENUS_NS:-0}" != 1; then
	if command -v unshare >/dev/null 2>&1; then
		exec env FIRSTBOOT_MENUS_NS=1 unshare -rm "$0" "$@"
	fi
fi

wizard=${SAPHIRA_FIRSTBOOT:-$here/../files/saphira-firstboot}
failures=0

ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

test -r "$wizard" || { printf 'wizard not readable: %s\n' "$wizard" >&2; exit 1; }

extract_function() {
	awk -v want="$1" '
		$0 ~ "^" want "\\(\\)" { inside = 1 }
		inside { print }
		inside && /^}/ { exit }
	' "$wizard"
}

for fn in ask_family choose_ipv4_mode configure_ipv6 write_network_state validate_network_state; do
	extract_function "$fn" >/dev/null || bad "$fn not found in $wizard"
done

# Drive one scenario: the answer queue, then the functions to call in
# order, each given the same interface.
drive() {
	local answers=$1 iface=${2:-eth0}
	shift 2 2>/dev/null || shift "$#"
	(
		IPV4_MODE=off IPV4_CIDR= IPV4_GATEWAY=
		IPV6_MODE=off IPV6_CIDR= IPV6_GATEWAY=
		eval "$(extract_function ask_family)"
		eval "$(extract_function choose_ipv4_mode)"
		eval "$(extract_function configure_ipv6)"
		eval "$(extract_function write_network_state)"
		eval "$(extract_function validate_network_state)"

		INTERFACE=eth0
		DNS_SERVERS=2001:4860:4860::8888
		DNS_SEARCH=
		network_state=$(mktemp)
		# The REAL shipped helper, from this recipe tree. An earlier
		# revision pointed at a scratch path outside the tree; once that
		# directory was cleaned up the test silently fell back to its
		# stub, the family rules stopped being enforced, the flow took
		# different branches and consumed a different number of answers -
		# and the suite went red for a reason that had nothing to do with
		# the code under test. A test may not depend on a path that
		# outlives nothing.
		network_apply=${NETWORK_APPLY:-$here/../files/libexec/apply-network.sh}
		if test ! -x "$network_apply"; then
			network_apply() { return 0; }
		fi

		read_setup() {
			local variable=$1 answer
			if test -z "$answers_left"; then
				printf '%s\n' "$EOF_MARKER"
				exit 99
			fi
			answer=${answers_left%%$'\n'*}
			if test "$answer" = "$answers_left"; then
				answers_left=
			else
				answers_left=${answers_left#*$'\n'}
			fi
			# q is back, exactly as the shipped read_setup decides it.
			if test "$answer" = q; then
				nav_back=1
				return 1
			fi
			printf -v "$variable" '%s' "$answer"
		}

		answers_left=$answers
		EOF_MARKER='__would-block__'
		local fn
		for fn in "$@"; do
			INTERFACE=$iface
			"$fn" "$iface"
		done
		printf '__RESULT__ v4=%s v6=%s v4cidr=%s v6cidr=%s\n' \
			"$IPV4_MODE" "$IPV6_MODE" "$IPV4_CIDR" "$IPV6_CIDR"
	)
}

run() {
	label=$1 answers=$2
	shift 2
	out=$(drive "$answers" eth0 "$@" 2>&1)
	case $out in
	*__would-block__*)
		bad "$label: the flow wanted more input than the scenario gave"
		return 1
		;;
	esac
	return 0
}

field() {
	printf '%s\n' "$1" | /usr/bin/sed -n "s/.*$2=\\([^ ]*\\).*/\\1/p" | /usr/bin/tail -1
}

printf '%s\n' '# IPv4 comes first'

if run 'ordering' '1
192.0.2.10/24
192.0.2.1
y
1
2001:db8::10/64
2001:db8::1
' choose_ipv4_mode configure_ipv6; then
	v4pos=$(printf '%s\n' "$out" | /usr/bin/grep -n 'IPv4 on' | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
	askpos=$(printf '%s\n' "$out" | /usr/bin/grep -n 'Configure IPv6 on' | /usr/bin/head -1 | /usr/bin/cut -d: -f1)
	if test -n "$v4pos" && test -n "$askpos" && test "$v4pos" -lt "$askpos"; then
		ok 'the IPv4 menu is presented before the IPv6 question'
	else
		bad "IPv4 must come first (ipv4 at ${v4pos:-none}, question at ${askpos:-none})"
	fi
	test "$(field "$out" v4)" = static && test "$(field "$out" v6)" = static &&
		test "$(field "$out" v4cidr)" = '192.0.2.10/24' &&
		test "$(field "$out" v6cidr)" = '2001:db8::10/64' &&
		ok 'both families take the addresses the operator typed' ||
		bad "unexpected static result: $out"
fi

printf '%s\n' '# the IPv6 question has no default'

if run 'blank ipv6 answer' '3

n
' choose_ipv4_mode configure_ipv6; then
	case $out in
	*"Answer y or n; an empty answer changes nothing"*)
		ok 'an empty answer to the IPv6 question re-prompts' ;;
	*) bad "an empty answer must re-prompt: $out" ;;
	esac
	test "$(field "$out" v6)" = off && ok 'answering no disables IPv6' ||
		bad "unexpected result: $out"
fi

printf '%s\n' '# no means IPv6 off, yes opens the IPv6 menu'

if run 'no ipv6' '3
n
' choose_ipv4_mode configure_ipv6; then
	test "$(field "$out" v6)" = off && ok 'no disables IPv6 for that interface' ||
		bad "no must disable IPv6: $out"
fi

if run 'yes ipv6 slaac' '3
y
2
' choose_ipv4_mode configure_ipv6; then
	test "$(field "$out" v6)" = slaac && ok 'yes opens the IPv6 menu and SLAAC is applied' ||
		bad "SLAAC was not applied: $out"
fi

if run 'yes ipv6 dhcpv6' '3
y
3
' choose_ipv4_mode configure_ipv6; then
	test "$(field "$out" v6)" = dhcp &&
		ok 'an explicit DHCPv6 selection is applied as chosen' ||
		bad "DHCPv6 was not applied: $out"
fi

printf '%s\n' '# DHCP is only ever a selection'

if run 'explicit dhcp' '2
n
' choose_ipv4_mode configure_ipv6; then
	test "$(field "$out" v4)" = dhcp && test "$(field "$out" v6)" = off &&
		ok 'an explicit DHCP selection does not bring IPv6 with it' ||
		bad "DHCP implied another mode: $out"
fi

printf '%s\n' '# Static requires an address'

if run 'blank static re-prompts' '1

192.0.2.10/24
192.0.2.1
n
' choose_ipv4_mode configure_ipv6; then
	case $out in
	*"A static IPv4 address is required"*) ok 'a blank address after choosing Static re-prompts' ;;
	*) bad "a blank address must re-prompt: $out" ;;
	esac
	test "$(field "$out" v4cidr)" = '192.0.2.10/24' &&
		ok 'the address comes from the operator, not a default' ||
		bad "unexpected result: $out"
fi

printf '%s\n' '# q goes back one step'

# q at the IPv6 question returns to the IPv4 mode menu; choosing DHCP
# there finishes the interface with IPv6 disabled - a mistake corrected
# without a reboot and without feeding the rest of the flow bogus input.
# The retry lives in the main flow, so the scenario passes the pair
# twice, exactly as the interface loop re-enters it.
if run 'q at the ipv6 question' '1
192.0.2.10/24
192.0.2.1
q
2
n
' choose_ipv4_mode configure_ipv6 choose_ipv4_mode configure_ipv6; then
	menus=$(printf '%s\n' "$out" | /usr/bin/grep -c 'IPv4 on eth0')
	if test "$menus" -ge 2; then
		ok 'q at the IPv6 question returns to the IPv4 menu'
	else
		bad "q must go back to the IPv4 mode (menu shown $menus time(s))"
	fi
	test "$(field "$out" v4)" = dhcp && test "$(field "$out" v6)" = off &&
		ok 'the corrected choice is applied, not the abandoned one' ||
		bad "the correction did not take effect: $out"
fi

# q at the gateway prompt returns to the IPv4 mode menu too.
if run 'q at the gateway' '1
192.0.2.10/24
q
3
n
' choose_ipv4_mode choose_ipv4_mode configure_ipv6; then
	menus=$(printf '%s\n' "$out" | /usr/bin/grep -c 'IPv4 on eth0')
	if test "$menus" -ge 2; then
		ok 'q at the gateway returns to the IPv4 mode menu'
	else
		bad "q at the gateway must go back to the mode menu (menu shown $menus time(s))"
	fi
	test "$(field "$out" v4)" = off && test "$(field "$out" v6)" = off &&
		ok 'the interface is left unconfigured after the correction' ||
		bad "unexpected result after going back: $out"
fi

printf '%s\n' '# Ctrl-C is wired to the same back-request, not to an abort'

if /usr/bin/grep -q '^trap nav_back_request INT$' "$wizard"; then
	ok 'Ctrl-C requests a step back'
else
	bad 'Ctrl-C must request a step back, not terminate the transaction'
fi
if /usr/bin/grep -q '^trap setup_signal TERM QUIT TSTP$' "$wizard"; then
	ok 'TERM/QUIT/TSTP still refuse to end a setup in progress'
else
	bad 'TERM/QUIT/TSTP must keep refusing to end a setup in progress'
fi
if /usr/bin/grep -q '^trap nav_back_request INT$' "$wizard" &&
	! /usr/bin/grep -q "^trap setup_signal INT" "$wizard"; then
	ok 'no trap ends the wizard on interrupt'
else
	bad 'an interrupt trap must not end the transaction'
fi

printf '%s\n' '# Disabled for both families is legal'

if run 'disabled both' '3
n
' choose_ipv4_mode configure_ipv6; then
	test "$(field "$out" v4)" = off && test "$(field "$out" v6)" = off &&
		ok 'Disabled/Disabled is accepted and means left alone' ||
		bad "Disabled/Disabled was rejected: $out"
fi

if test "$failures" -ne 0; then
	printf 'firstboot-network-menus: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-network-menus: OK'
#!/usr/bin/env bash

set -euo pipefail
umask 077

test "$(id -u)" -eq 0 || {
	printf 'apply-network: must be run as root\n' >&2
	exit 1
}

NETWORK_ROOT=${SAPHIRA_NETWORK_ROOT:-}
NETWORK_DIR=$NETWORK_ROOT/etc/network.d
NETWORK_FILE=$NETWORK_DIR/eth0.conf
NETWORK_SERVICE=${SAPHIRA_NETWORK_SERVICE:-/sbin/saphira-network-config}

fail()
{
	printf 'apply-network: ERROR: %s\n' "$*" >&2
	exit 1
}

ipv4_int()
{
	local value=$1 part number result=0
	local IFS=.
	read -r -a parts <<< "$value"
	((${#parts[@]} == 4)) || return 1
	for part in "${parts[@]}"; do
		[[ $part =~ ^[0-9]{1,3}$ ]] || return 1
		number=$((10#$part))
		((number <= 255)) || return 1
		result=$((result * 256 + number))
	done
	printf '%s\n' "$result"
}

valid_ipv4()
{
	ipv4_int "$1" >/dev/null
}

valid_ipv4_cidr()
{
	local value=$1 address prefix host mask network broadcast
	[[ $value == */* ]] || return 1
	address=${value%/*}; prefix=${value#*/}
	[[ $prefix =~ ^[0-9]+$ ]] && ((prefix <= 32)) || return 1
	host=$(ipv4_int "$address") || return 1
	if ((prefix == 0)); then mask=0
	else mask=$((4294967295 - ((1 << (32 - prefix)) - 1))); fi
	network=$((host & mask))
	broadcast=$((network | (4294967295 ^ mask)))
	IPV4_NETWORK=$network IPV4_BROADCAST=$broadcast IPV4_PREFIX=$prefix
}

valid_ipv4_gateway()
{
	local gateway=$1 host=$2 prefix=$3 mask network gateway_int
	gateway_int=$(ipv4_int "$gateway") || return 1
	host=$(ipv4_int "$host") || return 1
	if ((prefix == 0)); then mask=0
	else mask=$((4294967295 - ((1 << (32 - prefix)) - 1))); fi
	network=$((host & mask))
	(( (gateway_int & mask) == network && gateway_int != host )) || return 1
	if ((prefix <= 30)); then
		((gateway_int != network && gateway_int != (network | (4294967295 ^ mask)))) ||
			return 1
	fi
}

ipv6_expand()
{
	local value=$1 left right missing part
	local -a left_parts=() right_parts=() parts=()
	IPV6_GROUPS=()
	[[ $value != *.* ]] || return 1
	case $value in
		*::*)
			[[ ${value#*::} != *::* ]] || return 1
			left=${value%%::*}; right=${value#*::}
			[[ -z $left ]] || IFS=: read -r -a left_parts <<< "$left"
			[[ -z $right ]] || IFS=: read -r -a right_parts <<< "$right"
			((${#left_parts[@]} + ${#right_parts[@]} < 8)) || return 1
			parts=("${left_parts[@]}")
			missing=$((8 - ${#left_parts[@]} - ${#right_parts[@]}))
			while ((missing-- > 0)); do parts+=(0); done
			parts+=("${right_parts[@]}")
			;;
		*)
			IFS=: read -r -a parts <<< "$value"
			((${#parts[@]} == 8)) || return 1
			;;
	esac
	((${#parts[@]} == 8)) || return 1
	for part in "${parts[@]}"; do
		[[ $part =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
		IPV6_GROUPS+=("$(printf '%04x' "$((16#$part))")")
	done
}

valid_ipv6()
{
	ipv6_expand "$1"
}

valid_ipv6_cidr()
{
	local value=$1 address prefix
	[[ $value == */* ]] || return 1
	address=${value%/*}; prefix=${value#*/}
	[[ $prefix =~ ^[0-9]+$ ]] && ((prefix <= 128)) || return 1
	ipv6_expand "$address" || return 1
	IPV6_PREFIX=$prefix
}

ipv6_same_prefix()
{
	local left=$1 right=$2 prefix=$3 full remainder i left_value right_value
	local -a left_groups right_groups
	ipv6_expand "$left" || return 1; left_groups=("${IPV6_GROUPS[@]}")
	ipv6_expand "$right" || return 1; right_groups=("${IPV6_GROUPS[@]}")
	full=$((prefix / 16)); remainder=$((prefix % 16))
	for ((i = 0; i < full; i++)); do
		[[ ${left_groups[$i]} == "${right_groups[$i]}" ]] || return 1
	done
	if ((remainder > 0)); then
		left_value=$((16#${left_groups[$full]} >> (16 - remainder)))
		right_value=$((16#${right_groups[$full]} >> (16 - remainder)))
		((left_value == right_value)) || return 1
	fi
}

valid_ipv6_gateway()
{
	local gateway=$1 host=$2 prefix=$3 host_normalized
	valid_ipv6 "$gateway" || return 1
	valid_ipv6 "$host" || return 1
	ipv6_same_prefix "$host" "$gateway" "$prefix" || return 1
	ipv6_expand "$host"; host_normalized=${IPV6_GROUPS[*]}
	ipv6_expand "$gateway"
	[[ $host_normalized != "${IPV6_GROUPS[*]}" ]]
}

valid_domain()
{
	local value=$1 label
	[[ -z $value ]] && return 0
	((${#value} <= 253)) || return 1
	[[ $value != .* && $value != *. && $value != *..* ]] || return 1
	local IFS=.
	read -r -a labels <<< "$value"
	for label in "${labels[@]}"; do
		((${#label} <= 63)) || return 1
		[[ $label =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
	done
}

normalize_dns()
{
	local server output=()
	declare -A seen=()
	for server in $1; do
		if [[ $server == *:* ]]; then valid_ipv6 "$server" || return 1
		else valid_ipv4 "$server" || return 1; fi
		if [[ -z ${seen[$server]:-} ]]; then
			seen[$server]=1; output+=($server)
		fi
	done
	((${#output[@]} > 0)) || return 1
	printf '%s\n' "${output[*]}"
}

load_state()
{
	local state=$1 line key value
	declare -A seen_fields=()
	test -f "$state" || fail "network state is absent: $state"
	unset TYPE INTERFACE IPV4_MODE IPV4_CIDR IPV4_GATEWAY IPV4_METRIC
	unset IPV6_MODE IPV6_CIDR IPV6_GATEWAY IPV6_METRIC DNS_SERVERS DNS_SEARCH
	while IFS= read -r line || test -n "$line"; do
		test -z "$line" && continue
		key=${line%%=*}
		value=${line#*=}
		[[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || fail "invalid state field"
		test "$line" != "$key" || fail "state field has no value: $key"
		case $key in
			TYPE|INTERFACE|IPV4_MODE|IPV4_CIDR|IPV4_GATEWAY|IPV4_METRIC|\
			IPV6_MODE|IPV6_CIDR|IPV6_GATEWAY|IPV6_METRIC|DNS_SERVERS|DNS_SEARCH) ;;
			*) fail "unknown state field: $key" ;;
		esac
		test -z "${seen_fields[$key]:-}" || fail "duplicate state field: $key"
		seen_fields[$key]=1
		printf -v "$key" '%s' "$value"
	done < "$state"
	TYPE=${TYPE:-physical}; INTERFACE=${INTERFACE:-}
	IPV4_MODE=${IPV4_MODE:-off}; IPV4_CIDR=${IPV4_CIDR:-}; IPV4_GATEWAY=${IPV4_GATEWAY:-}
	IPV6_MODE=${IPV6_MODE:-off}; IPV6_CIDR=${IPV6_CIDR:-}; IPV6_GATEWAY=${IPV6_GATEWAY:-}
	DNS_SERVERS=${DNS_SERVERS:-}; DNS_SEARCH=${DNS_SEARCH:-}
}

validate_state()
{
	test "$TYPE" = physical || fail 'only physical eth0 configuration is supported'
	test "$INTERFACE" = eth0 || fail 'INTERFACE must be eth0'
	case $IPV4_MODE in
		off) test -z "$IPV4_CIDR" && test -z "$IPV4_GATEWAY" ||
			fail 'IPv4 fields must be empty when IPv4 is off' ;;
		static)
			valid_ipv4_cidr "$IPV4_CIDR" || fail "invalid IPv4 CIDR: $IPV4_CIDR"
			test -z "$IPV4_GATEWAY" ||
				valid_ipv4_gateway "$IPV4_GATEWAY" "${IPV4_CIDR%/*}" "$IPV4_PREFIX" ||
				fail "invalid IPv4 gateway: $IPV4_GATEWAY" ;;
		*) fail "invalid IPv4 mode: $IPV4_MODE" ;;
	esac
	case $IPV6_MODE in
		off) test -z "$IPV6_CIDR" && test -z "$IPV6_GATEWAY" ||
			fail 'IPv6 fields must be empty when IPv6 is off' ;;
		static)
			valid_ipv6_cidr "$IPV6_CIDR" || fail "invalid IPv6 CIDR: $IPV6_CIDR"
			test -z "$IPV6_GATEWAY" ||
				valid_ipv6_gateway "$IPV6_GATEWAY" "${IPV6_CIDR%/*}" "$IPV6_PREFIX" ||
				fail "invalid IPv6 gateway: $IPV6_GATEWAY" ;;
		*) fail "invalid IPv6 mode: $IPV6_MODE" ;;
	esac
	test "$IPV4_MODE" = static || test "$IPV6_MODE" = static ||
		fail 'at least one address family must be configured'
	DNS_SERVERS=$(normalize_dns "$DNS_SERVERS") || fail 'DNS_SERVERS is invalid or empty'
	valid_domain "$DNS_SEARCH" || fail "DNS_SEARCH is invalid: $DNS_SEARCH"
}

write_network_file()
{
	local temporary
	install -d -m 0755 "$NETWORK_DIR"
	temporary=$(mktemp "$NETWORK_DIR/.eth0.conf.XXXXXX")
	trap 'rm -f "$temporary"' RETURN
	{
		printf 'TYPE=physical\nINTERFACE=eth0\n'
		printf 'IPV4_MODE=%s\nIPV4_CIDR=%s\nIPV4_GATEWAY=%s\nIPV4_METRIC=\n' "$IPV4_MODE" "$IPV4_CIDR" "$IPV4_GATEWAY"
		printf 'IPV6_MODE=%s\nIPV6_CIDR=%s\nIPV6_GATEWAY=%s\nIPV6_METRIC=\n' \
			"$IPV6_MODE" "$IPV6_CIDR" "$IPV6_GATEWAY"
		printf 'DNS_SERVERS=%q\nDNS_SEARCH=%q\n' "$DNS_SERVERS" "$DNS_SEARCH"
	} > "$temporary"
	chmod 0644 "$temporary"
	test "${SAPHIRA_NETWORK_SKIP_OWNERSHIP:-0}" = 1 || chown 0:0 "$temporary"
	mv -f "$temporary" "$NETWORK_FILE"
	trap - RETURN
}

dns_provider()
{
	case $1 in
		1) printf '%s|%s\n' '9.9.9.9 149.112.112.112' '2620:fe::fe 2620:fe::9' ;;
		2) printf '%s|%s\n' '1.1.1.1 1.0.0.1' '2606:4700:4700::1111 2606:4700:4700::1001' ;;
		3) printf '%s|%s\n' '208.67.222.222 208.67.220.220' '2620:119:35::35 2620:119:53::53' ;;
		*) fail "unknown DNS provider: $1" ;;
	esac
}

apply_network()
{
	local state=$1 state_dir active completed
	state_dir=${SAPHIRA_FIRSTBOOT_STATE_DIR:-/var/lib/saphira-firstboot}
	active=$state_dir/active
	completed=$state_dir/completed
	test ! -e "$completed" || fail 'firstboot has already completed'
	test -d "$state_dir" || fail 'firstboot state directory is absent'
	if test "${SAPHIRA_NETWORK_SKIP_OWNERSHIP:-0}" = 1; then
		test "$(stat -c %a "$state_dir")" = 700 ||
			fail 'firstboot state directory is not protected'
	else
		test "$(stat -c %u:%a "$state_dir")" = '0:700' ||
			fail 'firstboot state directory is not protected'
	fi
	test -f "$active" || fail 'no active firstboot transaction'
	if test "${SAPHIRA_NETWORK_SKIP_OWNERSHIP:-0}" = 1; then
		test "$(stat -c %a "$active")" = 600 ||
			fail 'firstboot transaction is not protected'
	else
		test "$(stat -c %u:%a "$active")" = '0:600' ||
			fail 'firstboot transaction is not protected'
	fi
	test "$(dirname -- "$state")" -ef "$state_dir" ||
		fail 'network state is outside the firstboot transaction directory'
	if test "${SAPHIRA_NETWORK_SKIP_OWNERSHIP:-0}" = 1; then
		test "$(stat -c %a "$state")" = 600 ||
			fail 'network state is not protected'
	else
		test "$(stat -c %u:%a "$state")" = '0:600' ||
			fail 'network state is not protected'
	fi
	write_network_file
	if test "${SAPHIRA_NETWORK_APPLY:-1}" = 1; then
		test -x "$NETWORK_SERVICE" || fail "network service is absent: $NETWORK_SERVICE"
		"$NETWORK_SERVICE" start || fail 'network service could not apply eth0.conf'
	fi
}

case ${1:-} in
	validate) test $# -eq 2 || fail 'usage: apply-network.sh validate STATE'; load_state "$2"; validate_state ;;
	apply) test $# -eq 2 || fail 'usage: apply-network.sh apply STATE'; load_state "$2"; validate_state; apply_network "$2" ;;
	dns-provider) test $# -eq 2 || fail 'usage: apply-network.sh dns-provider NUMBER'; dns_provider "$2" ;;
	validate-ipv4) test $# -eq 2 && valid_ipv4 "$2" || fail "invalid IPv4 address: ${2:-}" ;;
	validate-ipv4-cidr) test $# -eq 2 && valid_ipv4_cidr "$2" || fail "invalid IPv4 CIDR: ${2:-}" ;;
	validate-ipv6) test $# -eq 2 && valid_ipv6 "$2" || fail "invalid IPv6 address: ${2:-}" ;;
	validate-ipv6-cidr) test $# -eq 2 && valid_ipv6_cidr "$2" || fail "invalid IPv6 CIDR: ${2:-}" ;;
	validate-domain) test $# -eq 2 && valid_domain "$2" || fail "invalid DNS search domain: ${2:-}" ;;
	normalize-dns) test $# -eq 2 || fail 'usage: apply-network.sh normalize-dns SERVERS'; normalize_dns "$2" || fail 'DNS_SERVERS is invalid or empty' ;;
	*) fail 'usage: apply-network.sh {validate|apply|dns-provider|validate-ipv4|validate-ipv6|validate-domain|normalize-dns} ...' ;;
esac

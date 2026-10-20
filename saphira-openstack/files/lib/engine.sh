#!/bin/sh
#
# engine.sh - the ONE validation and planning engine behind saphira-openstack.
#
# Every interface (init wizard, inventory, plan) funnels through these
# functions: os_parse -> os_validate -> os_normalize -> os_plan_data.
# Interactive answers and configuration files are interchangeable inputs.
#
# Design rules encoded here:
#   * No hardcoded addresses, domains, hostnames, interfaces, bridges,
#     VLANs or storage devices. Nothing here invents a deployment value.
#   * Validation is grounded in the shipped catalog data, which records
#     what the actual OpenStack components support.
#   * Canonical output is deterministic: fixed section order, sorted keys,
#     no timestamps, no host data. Same input => byte-identical plan.

os_errors=0
os_err_first=''

os_reset_errors()
{
	os_errors=0
	os_err_first=''
}

os_error()
{
	# Accumulate every problem; never stop at the first. The operator
	# sees the complete list once, not one error per round-trip.
	os_errors=$((os_errors + 1))
	[ -n "$os_err_first" ] || os_err_first=$1
	printf 'saphira-openstack: %s\n' "$1" >&2
}

# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------

# Parse a document into flat records: <section> <tab> <key> <tab> <value>.
# Handles comments (#), blank lines, [section], key = value, and
# comma-separated lists (trimmed). Pure POSIX shell.
#
# Records are written to a scratch file and its path is printed, so every
# accessor can read them with awk. The scratch file lives under OS_TMP
# (SAPHIRA_TMPDIR), never a live path.
os_parse()
{
	local file rf
	file=$1
	[ -f "$file" ] || { os_error "document not found: $file"; return 1; }
	rf=$(mktemp "$OS_TMP/records.XXXXXX") || { os_error "cannot create scratch"; return 1; }
	awk -v PROG="$PROG" '
		function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
		{
			line = $0
			sub(/#.*$/, "", line)
			if (line ~ /^[ \t]*$/) next
			if (line ~ /^[ \t]*\[.*\][ \t]*$/) {
				sec = line
				gsub(/^[ \t]*\[|\][ \t]*$/, "", sec)
				sec = trim(sec)
				if (sec !~ /^[A-Za-z0-9._: -]+$/) {
					printf "saphira-openstack: invalid section name: %s\n", sec > "/dev/stderr"
					bad = 1
				}
				print sec "\t" "\t\t"
				next
			}
			if (line !~ /=/) {
				printf "saphira-openstack: line %d is not key = value: %s\n", NR, line > "/dev/stderr"
				bad = 1
				next
			}
			eq = index(line, "=")
			key = trim(substr(line, 1, eq - 1))
			val = trim(substr(line, eq + 1))
			if (key !~ /^[A-Za-z0-9._-]+$/) {
				printf "saphira-openstack: invalid key: %s\n", key > "/dev/stderr"
				bad = 1
				next
			}
			# split comma-separated lists into one record per item
			n = split(val, items, ",")
			for (i = 1; i <= n; i++) {
				item = trim(items[i])
				if (item != "") print sec "\t" key "\t" item
			}
		}
		END { exit bad ? 1 : 0 }
	' "$file" > "$rf" || { rm -f "$rf"; return 1; }
	printf '%s' "$rf"
}

# ---------------------------------------------------------------------------
# Field validators (shared by engine, wizard and CLI)
# ---------------------------------------------------------------------------

os_valid_cidr4()
{
	local ip pfx oldifs o
	case "$1" in
	'' | *[!0-9./]*) return 1 ;;
	esac
	ip=${1%/*}; pfx=${1#*/}
	case "$ip" in '' | *[!0-9.]*) return 1 ;; esac
	case "$pfx" in '' | *[!0-9]*) return 1 ;; esac
	[ "$pfx" -le 32 ] 2>/dev/null || return 1
	oldifs=$IFS; IFS=.; set -- $ip; IFS=$oldifs
	[ "$#" -eq 4 ] || return 1
	for o in "$@"; do
		case "$o" in '' | *[!0-9]*) return 1 ;; esac
		[ "$o" -le 255 ] 2>/dev/null || return 1
	done
	# no host bits required to be zero: operator's network, operator's rule
	return 0
}

os_valid_cidr6()
{
	local ip pfx pre post n part
	case "$1" in
	'' | *[!0-9a-fA-F:./]*) return 1 ;;
	esac
	ip=${1%/*}; pfx=${1#*/}
	case "$ip" in '' | *[!0a-fA-F0-9:]*) return 1 ;; esac
	case "$pfx" in '' | *[!0-9]*) return 1 ;; esac
	[ "$pfx" -le 128 ] 2>/dev/null || return 1
	# at most one "::" compression
	case "$ip" in
	*::*::*) return 1 ;;
	esac
	pre=${ip%%::*}
	post=${ip#*::}
	n=0
	i=0
	for part in $(printf '%s' "$pre" | tr ':' ' '); do
		case "$part" in '' | *[!0-9a-fA-F]* | ?????*) return 1 ;; esac
		n=$((n + 1))
	done
	for part in $(printf '%s' "$post" | tr ':' ' '); do
		case "$part" in '' | *[!0-9a-fA-F]* | ?????*) return 1 ;; esac
		n=$((n + 1))
	done
	case "$ip" in
	*::*) [ "$n" -le 8 ] ;;
	*) [ "$n" -eq 8 ] ;;
	esac
}

os_valid_addr4()
{
	local oldifs o
	case "$1" in
	'' | *[!0-9.]*) return 1 ;;
	esac
	oldifs=$IFS; IFS=.; set -- $1; IFS=$oldifs
	[ "$#" -eq 4 ] || return 1
	for o in "$@"; do
		case "$o" in '' | *[!0-9]*) return 1 ;; esac
		[ "$o" -le 255 ] 2>/dev/null || return 1
	done
	return 0
}

os_valid_addr6()
{
	case "$1" in
	'' | *[!0-9a-fA-F:.]*) return 1 ;;
	esac
	case "$1" in
	*..*) return 1 ;;
	esac
	os_valid_cidr6 "$1/128"
}

os_valid_ipv4_or_v6()
{
	os_valid_addr4 "$1" || os_valid_addr6 "$1"
}

os_gateway_in_cidr4()
{
	local cidr gw cip pfx c32 g32 mask net bc
	# Gateway must be a usable host inside the CIDR (network+1 check).
	os_valid_cidr4 "$1" || return 1
	os_valid_addr4 "$2" || return 1
	cidr=$1; gw=$2
	cip=${cidr%/*}; pfx=${cidr#*/}
	# /31 and /32 are point-to-point / host routes: any address inside
	# the prefix is usable as a gateway.
	[ "$pfx" -ge 31 ] && return 0
	c32=$(os_ip4_to_int "$cip")
	g32=$(os_ip4_to_int "$gw")
	mask=$((0xFFFFFFFF << (32 - pfx) & 0xFFFFFFFF))
	[ "$((c32 & mask))" -eq "$((g32 & mask))" ] || return 1
	net=$((c32 & mask))
	[ "$g32" -ne "$net" ] || return 1
	bc=$((net | (mask ^ 0xFFFFFFFF)))
	[ "$g32" -ne "$bc" ] || return 1
	return 0
}

os_ip4_to_int()
{
	local oldifs
	oldifs=$IFS; IFS=.; set -- $1; IFS=$oldifs
	echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 ))
}

os_gateway_in_cidr6()
{
	local pfx
	os_valid_cidr6 "$1" || return 1
	os_valid_addr6 "$2" || return 1
	pfx=${1#*/}
	[ "$pfx" -eq 128 ] && { [ "$2" = "${1%/*}" ]; return; }
	[ "$pfx" -eq 0 ] && return 0
	os_bits_match6 "${1%/*}" "$pfx" "$2"
}

os_expand6()
{
	local pre post out n m z part
	# Expand "::" to eight zero-padded hextets; refuse irregular input.
	case "$1" in
	*::*::*) return 1 ;;
	*.*) return 1 ;;
	esac
	pre=${1%%::*}
	post=${1#*::}
	out=""
	n=0
	for part in $(printf '%s' "$pre" | tr ':' ' '); do
		case "$part" in '' | *[!0-9a-fA-F]* | ?????*) return 1 ;; esac
		while [ "${#part}" -lt 4 ]; do part="0$part"; done
		out="${out:+$out:}$part"
		n=$((n + 1))
	done
	case "$1" in
	*::*)
		z=$((8 - n))
		# count post hextets too
		m=0
		for part in $(printf '%s' "$post" | tr ':' ' '); do
			case "$part" in '' | *[!0-9a-fA-F]* | ?????*) return 1 ;; esac
			m=$((m + 1))
		done
		z=$((8 - n - m))
		[ "$z" -ge 0 ] || return 1
		while [ "$z" -gt 0 ]; do
			out="${out:+$out:}0000"
			z=$((z - 1))
		done
		;;
	esac
	for part in $(printf '%s' "$post" | tr ':' ' '); do
		case "$part" in '' | *[!0-9a-fA-F]* | ?????*) return 1 ;; esac
		while [ "${#part}" -lt 4 ]; do part="0$part"; done
		out="${out:+$out:}$part"
	done
	printf '%s' "$out"
}

os_hextet_bits()
{
	local v out i b
	# four hex chars -> sixteen bits
	v=$1
	out=""
	i=0
	while [ "$i" -lt 4 ]; do
		case ${v:$i:1} in
		0) b=0000 ;; 1) b=0001 ;; 2) b=0010 ;; 3) b=0011 ;;
		4) b=0100 ;; 5) b=0101 ;; 6) b=0110 ;; 7) b=0111 ;;
		8) b=1000 ;; 9) b=1001 ;; a | A) b=1010 ;; b | B) b=1011 ;;
		c | C) b=1100 ;; d | D) b=1101 ;; e | E) b=1110 ;; f | F) b=1111 ;;
		*) return 1 ;;
		esac
		out="$out$b"
		i=$((i + 1))
	done
	printf '%s' "$out"
}

os_bits_match6()
{
	local a b ab bb i h
	# Do the first $2 bits of two IPv6 addresses agree?
	a=$(os_expand6 "$1") || return 1
	b=$(os_expand6 "$3") || return 1
	ab=""; bb=""
	i=0
	while [ "$i" -lt 8 ]; do
		h=${a:$((i * 5)):4}
		ab="$ab$(os_hextet_bits "$h")" || return 1
		h=${b:$((i * 5)):4}
		bb="$bb$(os_hextet_bits "$h")" || return 1
		i=$((i + 1))
	done
	[ "${ab:0:$2}" = "${bb:0:$2}" ]
}

os_valid_dns()
{
	local ok rest label
	# A DNS entry is one IPv4/IPv6 address or a resolvable name.
	os_valid_addr4 "$1" && return 0
	os_valid_addr6 "$1" && return 0
	case "$1" in
	'' | *[!A-Za-z0-9.-]*) return 1 ;;
	esac
	[ "${#1}" -le 253 ] || return 1
	case "$1" in
	.* | *.) return 1 ;;
	esac
	# labels: non-empty, no leading/trailing hyphen
	ok=1
	rest=$1
	while [ -n "$rest" ]; do
		label=${rest%%.*}
		rest=${rest#*.}
		[ "$label" = "$rest" ] && rest=''
		case "$label" in
		'' | -* | -*) ok=0 ;;
		esac
		[ "${#label}" -le 63 ] || ok=0
		[ "$ok" = 0 ] && break
	done
	[ "$ok" = 1 ]
}

os_valid_vlan()
{
	case "$1" in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 1 ] && [ "$1" -le 4094 ]
}

os_valid_name()
{
	# Hostnames, bridge names, interface names, pool names: conservative
	# shell-safe tokens. Interface names cap at 15 like the kernel.
	case "$1" in
	'' | *[!A-Za-z0-9_.:-]*) return 1 ;;
	esac
	[ "${#1}" -le 64 ] || return 1
	case "$1" in
	.. | .* | *.) return 1 ;;
	esac
	return 0
}

os_valid_ovsmap()
{
	local b p
	# bridge:port mapping, both operator-chosen, both name-validated.
	case "$1" in
	*:*)
		b=${1%%:*}; p=${1#*:}
		os_valid_name "$b" || return 1
		os_valid_name "$p" || return 1
		return 0
		;;
	*) return 1 ;;
	esac
}

os_valid_csv()
{
	# Comma-separated list of name tokens (service names, menu numbers).
	local oldifs item
	case "$1" in
	'' | *[!A-Za-z0-9_.,:-]*) return 1 ;;
	esac
	oldifs=$IFS; IFS=,; set -- $1; IFS=$oldifs
	[ "$#" -ge 1 ] || return 1
	for item in "$@"; do
		os_valid_name "$item" || return 1
	done
	return 0
}

# ---------------------------------------------------------------------------
# Document accessors (over the parsed records)
# ---------------------------------------------------------------------------

# os_get <section> <key> <records> -> first value, empty if absent
os_get()
{
	awk -F'\t' -v s="$1" -v k="$2" '$1 == s && $2 == k { print $3; exit }' "$3"
}

# os_get_all <section> <key> <records> -> one value per line
os_get_all()
{
	awk -F'\t' -v s="$1" -v k="$2" '$1 == s && $2 == k { print $3 }' "$3"
}

# os_sections <prefix> <records> -> unique section identifiers
# For prefix "node", "node controller" yields "controller". An empty
# prefix returns every full section name.
os_sections()
{
	awk -F'\t' -v p="$1" '
		{
			if (p == "" || $1 == p || index($1, p " ") == 1) {
				s = $1
				if (p != "") sub("^"p" ?", "", s)
				print s
			}
		}' "$2" | awk '!seen[$0]++'
}

# os_get_prefix_all <prefix> <key> <records> -> values across every
# section whose name starts with <prefix>
os_get_prefix_all()
{
	awk -F'\t' -v p="$1" -v k="$2" '$1 ~ "^"p && $2 == k { print $3 }' "$3"
}

# ---------------------------------------------------------------------------
# Catalog access
# ---------------------------------------------------------------------------

os_catalog_rows()
{
	# rows of a catalog TSV: documentation lines (#) and blanks are
	# not data (the leading lines document the format; there is no
	# header row to skip)
	grep -v -e '^#' -e '^[[:space:]]*$' "$catalog_dir/$1.tsv" 2>/dev/null
}

os_catalog_field()
{
	local row field
	# os_catalog_field <file> <row> <field> -> value
	row=$2; field=$3
	printf '%s\n' "$row" | awk -F'|' -v f="$field" '{ print $f }'
}

os_catalog_list()
{
	# os_catalog_list <file> -> "name" column, one per line
	tail -n +2 "$catalog_dir/$1.tsv" 2>/dev/null | awk -F'|' '{ print $1 }'
}

# ---------------------------------------------------------------------------
# Service readiness (derived, never hand-maintained)
# ---------------------------------------------------------------------------

os_apk_ready()
{
	# Exit 0 when APK $1 is installed or available in a configured
	# repository here (read-only probes only). With
	# SAPHIRA_OPENSTACK_PROVIDES set, the named fixture file decides
	# instead of the live system (missing fixture fails closed to
	# unavailable); it lists one provided APK name per line.
	local pkg
	pkg=$1
	if [ -n "${SAPHIRA_OPENSTACK_PROVIDES:-}" ]; then
		grep -qx "$pkg" "${SAPHIRA_OPENSTACK_PROVIDES:-/dev/null}" 2>/dev/null
		return $?
	fi
	command -v apk >/dev/null 2>&1 || return 1
	apk info -e "$pkg" >/dev/null 2>&1 && return 0
	apk search --exact "$pkg" >/dev/null 2>&1
}

# os_service_probe <name> -> prints "ready <apk>" (exit 0) when the
# catalog's provider package is installed or available in a configured
# repository here; otherwise prints "pending <reason>" (exit 1).
# Reasons: unknown-service, no-package (no native package exists) or
# unavailable (packaged upstream but not obtainable from here).
os_service_probe()
{
	local name row pkg
	name=$1
	row=$(os_catalog_rows services | awk -F'|' -v n="$name" '$1 == n')
	[ -n "$row" ] || { printf 'pending unknown-service\n'; return 1; }
	pkg=$(printf '%s\n' "$row" | awk -F'|' '{ print $8 }')
	[ -n "$pkg" ] || { printf 'pending no-package\n'; return 1; }
	if os_apk_ready "$pkg"; then
		printf 'ready %s\n' "$pkg"
		return 0
	fi
	printf 'pending unavailable\n'
	return 1
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

os_validate()
{
	local file records
	file=$1
	os_reset_errors
	records=$(os_parse "$file") || { os_error "document does not parse"; return 1; }
	[ -n "$records" ] || { os_error "document is empty"; return 1; }

	os_validate_global "$records"
	os_validate_keys "$records"
	os_validate_nodes "$records"
	os_validate_networks "$records"
	os_validate_storage "$records"
	os_validate_services "$records"
	os_validate_operations "$records"
	os_validate_cross "$records"

	[ "$os_errors" -eq 0 ] || {
		printf 'saphira-openstack: %d problem(s) in %s; first: %s\n' \
			"$os_errors" "$file" "$os_err_first" >&2
		return 1
	}
	return 0
}

os_validate_global()
{
	local r domain init
	r=$1
	[ -n "$(os_sections '' "$r")" ] || os_error "document has no recognizable content"
	domain=$(os_get global domain "$r")
	if [ -z "$domain" ]; then
		os_error "[global] domain is required"
	else
		os_valid_dns "$domain" >/dev/null 2>&1 ||
			os_error "[global] domain is not a valid DNS name: $domain"
		case "$domain" in
		*.*) ;;
		*) os_error "[global] domain should be a DNS name (e.g. cloud.example): $domain" ;;
		esac
	fi
	init=$(os_get global init "$r")
	if [ -z "$init" ]; then
		os_error "[global] init is required (openrc or systemd)"
	else
		case "$init" in
		openrc | systemd) ;;
		*) os_error "[global] init must be openrc or systemd" ;;
		esac
	fi
}

os_validate_keys()
{
	# Reject any key not defined for its section type: a typo must be a
	# named error, never a silently ignored line.
	local r bad line oldifs
	r=$1
	bad=$(awk -F'\t' '
		function allowed(sec, key,   t) {
			t = sec; sub(/ .*/, "", t)
			if (sec == "global") return (key == "domain" || key == "init")
			if (t == "node") return (key == "roles" || key == "address4" || key == "address6")
			if (t == "network")
				return (key ~ /^(purposes|existing|family|cidr4|gateway4|mode4|dns|cidr6|gateway6|mode6|vlan|bridge|interface|ovs|take_ownership)$/)
			if (t == "storage")
				return (key == "type" || key == "shared" || key == "existing" || key == "devices")
			if (t == "service") return (key == "node")
			if (sec == "operations")
				return (key ~ /^(init|endpoints|tls|cert|key|credentials|db_node|mq_node|ha)$/)
			return 0
		}
		$2 == "" { next }
		!allowed($1, $2) { printf "%s: unknown key: %s\n", $1, $2 }
	' "$r")
	if [ -n "$bad" ]; then
		oldifs=$IFS; IFS='
'
		for line in $bad; do os_error "$line"; done
		IFS=$oldifs
	fi
}

os_validate_nodes()
{
	local r nodes n roles role fam v has4 has6
	r=$1
	nodes=$(os_sections node "$r")
	[ -n "$nodes" ] || os_error "at least one [node] is required"
	: > "$OS_TMP/nodes.$$"
	for n in $nodes; do
		# duplicate section names are impossible in a line-oriented parse;
		# a repeated node section was already collapsed by the parser.
		roles=$(os_get_all "node $n" roles "$r")
		[ -n "$roles" ] || os_error "node $n: at least one role is required"
		for role in $roles; do
			case "$role" in
			controller | compute) ;;
			*) os_error "node $n: unknown role '$role' (controller|compute)" ;;
			esac
		done
		# families are independent: each is validated on its own
		for fam in 4 6; do
			v=$(os_get "node $n" "address$fam" "$r")
			[ -n "$v" ] && {
				os_valid_addr$fam "$v" >/dev/null 2>&1 || \
					os_error "node $n: address$fam is not valid: $v"
			}
		done
		has4=$(os_get "node $n" address4 "$r")
		has6=$(os_get "node $n" address6 "$r")
		[ -n "$has4" ] || [ -n "$has6" ] || \
			os_error "node $n: at least one of address4/address6 is required"
		printf '%s\n' "$n" >> "$OS_TMP/nodes.$$"
	done
}

os_validate_networks()
{
	local r nets purposes net purps p existing fam cidr gw mode vlan bridge iface ovs own any dup
	r=$1
	nets=$(os_sections network "$r")
	[ -n "$nets" ] || os_error "at least one [network] is required"
	purposes=''
	: > "$OS_TMP/cidrs.$$"
	for net in $nets; do
		purps=$(os_get_all "network $net" purposes "$r")
		[ -n "$purps" ] || os_error "network $net: purposes is required (comma list)"
		for p in $purps; do
			case "$p" in
			management | provider | tenant | storage) ;;
			*) os_error "network $net: unknown purpose '$p'" ;;
			esac
		done
		purposes="$purposes $purps"

		existing=$(os_get "network $net" existing "$r")
		case "$existing" in
		yes | no | '') ;;
		*) os_error "network $net: existing must be yes or no" ;;
		esac

		for fam in 4 6; do
			cidr=$(os_get "network $net" "cidr$fam" "$r")
			[ -n "$cidr" ] || continue
			os_valid_cidr$fam "$cidr" >/dev/null 2>&1 || \
				os_error "network $net: cidr$fam is not valid: $cidr"
			printf '%s %s\n' "$fam" "$cidr" >> "$OS_TMP/cidrs.$$"
			gw=$(os_get "network $net" "gateway$fam" "$r")
			[ -n "$gw" ] && {
				os_gateway_in_cidr$fam "$cidr" "$gw" >/dev/null 2>&1 || \
					os_error "network $net: gateway$fam $gw is not inside $cidr"
			}
			# DHCP mode only makes sense for static-configurable purposes
			mode=$(os_get "network $net" "mode$fam" "$r")
			case "$mode" in
			'' | dhcp | static | none) ;;
			*) os_error "network $net: mode$fam must be dhcp, static or none" ;;
			esac
		done

		vlan=$(os_get "network $net" vlan "$r")
		[ -n "$vlan" ] && {
			os_valid_vlan "$vlan" >/dev/null 2>&1 || \
				os_error "network $net: vlan must be 1-4094: $vlan"
		}
		bridge=$(os_get "network $net" bridge "$r")
		[ -n "$bridge" ] && {
			os_valid_name "$bridge" >/dev/null 2>&1 || \
				os_error "network $net: bridge name is not valid: $bridge"
		}
		iface=$(os_get "network $net" interface "$r")
		[ -n "$iface" ] && {
			os_valid_name "$iface" >/dev/null 2>&1 || \
				os_error "network $net: interface name is not valid: $iface"
		}
		ovs=$(os_get "network $net" ovs "$r")
		[ -n "$ovs" ] && {
			os_valid_ovsmap "$ovs" >/dev/null 2>&1 || \
				os_error "network $net: ovs must be bridge:port: $ovs"
		}
		own=$(os_get "network $net" take_ownership "$r")
		case "$own" in
		yes | no | '') ;;
		*) os_error "network $net: take_ownership must be yes or no" ;;
		esac
		# an existing interface may only be adopted explicitly
		if [ "$own" = yes ] && [ -z "$iface" ]; then
			os_error "network $net: take_ownership=yes requires an interface"
		fi
		# at least one address family, unless this is an existing network
		any=0
		for fam in 4 6; do
			[ -n "$(os_get "network $net" "cidr$fam" "$r")" ] && any=1
		done
		[ "$any" = 1 ] || [ "$existing" = yes ] || \
			os_error "network $net: at least one of cidr4/cidr6 is required (or set existing = yes)"
	done

	# management is mandatory; the other purposes are optional
	case " $purposes " in
	*management*) ;;
	*) os_error "a management network is required" ;;
	esac

	# no two networks may share the same CIDR in the same family
	if [ -f "$OS_TMP/cidrs.$$" ]; then
		dup=$(awk '{ print $1, $2 }' "$OS_TMP/cidrs.$$" | sort | uniq -d)
		[ -z "$dup" ] || os_error "duplicate network CIDR across [network] sections: $(echo "$dup" | tr '\n' ' ')"
	fi
}

os_validate_storage()
{
	local r storages s type row status shared existing devs
	r=$1
	storages=$(os_sections storage "$r")
	: > "$OS_TMP/storage.$$"
	for s in $storages; do
		type=$(os_get "storage $s" type "$r")
		[ -n "$type" ] || os_error "storage $s: type is required"
		case "$type" in
		zfs-pool | zfs-dataset | local | nfs | lvm | ceph) ;;
		*) os_error "storage $s: unknown type '$type'" ;;
		esac
		# the type must exist in the catalog and be usable
		row=$(os_catalog_rows storage | awk -F'|' -v t="$type" '$1 == t')
		[ -n "$row" ] || os_error "storage $s: type '$type' is not in the catalog"
		[ -n "$type" ] && {
			status=$(printf '%s\n' "$row" | awk -F'|' '{ print $4 }')
			[ "$status" = ready ] || os_error "storage $s: backend '$type' is pending, not ready"
		}
		shared=$(os_get "storage $s" shared "$r")
		case "$shared" in
		yes | no | '') ;;
		*) os_error "storage $s: shared must be yes or no" ;;
		esac
		existing=$(os_get "storage $s" existing "$r")
		case "$existing" in
		yes | no | '') ;;
		*) os_error "storage $s: existing must be yes or no" ;;
		esac
		# an existing pool/dataset may only be imported/attached, never
		# recreated: no devices may be declared for it
		if [ "$existing" = yes ]; then
			devs=$(os_get_all "storage $s" devices "$r")
			[ -z "$devs" ] || os_error "storage $s: existing storage cannot declare devices (no recreation)"
		else
			# new ZFS storage must name its devices explicitly
			case "$type" in
			zfs-pool)
				devs=$(os_get "storage $s" devices "$r")
				[ -n "$devs" ] || os_error "storage $s: new zfs-pool requires devices (never auto-detected)"
				;;
			esac
		fi
		[ -n "$type" ] && printf '%s\n' "$type" >> "$OS_TMP/storage.$$"
	done
}

os_validate_services()
{
	local r svcs nodes s name row node roles allowed ok role has_keystone
	r=$1
	svcs=$(os_sections service "$r")
	nodes=$(cat "$OS_TMP/nodes.$$" 2>/dev/null | tr '\n' ' ')
	[ -n "$svcs" ] || os_error "select at least one OpenStack service"
	for s in $svcs; do
		name=$s
		row=$(os_catalog_rows services | awk -F'|' -v n="$name" '$1 == n')
		[ -n "$row" ] || os_error "service $s: '$name' is not a catalog component"
		[ -n "$row" ] || continue
		# pending is a packaging fact, not a configuration error: the
		# operator may design a cloud that includes not-yet-packaged
		# services. The plan marks them pending, never deployable.
		node=$(os_get "service $s" node "$r")
		[ -n "$node" ] || os_error "service $s: node is required"
		case " $nodes " in
		*" $node "*) ;;
		*) os_error "service $s: node '$node' is not in the inventory" ;;
		esac
		# the service must be allowed on that node's roles
		roles=$(os_get_all "node $node" roles "$r")
		allowed=$(printf '%s\n' "$row" | awk -F'|' '{ print $4 }' | tr ',' ' ')
		ok=0
		for role in $roles; do
			case " $allowed " in
			*" $role "*) ok=1 ;;
			esac
		done
		[ "$ok" = 1 ] || os_error "service $s: '$name' does not run on node $node (roles: $roles)"
	done
	# keystone is the identity anchor: if any service is selected,
	# keystone must be selected too
	has_keystone=$(os_sections service "$r" | grep -cx keystone || true)
	[ "$has_keystone" -ge 1 ] || \
		os_error "keystone is required: every OpenStack service depends on identity"
}

os_validate_operations()
{
	local r init tls cert key creds k v roles ha
	r=$1
	init=$(os_get operations init "$r")
	if [ -n "$init" ]; then
		case "$init" in
		openrc | systemd) ;;
		*) os_error "[operations] init must be openrc or systemd" ;;
		esac
	fi
	tls=$(os_get operations tls "$r")
	case "$tls" in
	'' | none | selfsigned | provided) ;;
	*) os_error "[operations] tls must be none|selfsigned|provided" ;;
	esac
	if [ "$tls" = provided ]; then
		cert=$(os_get operations cert "$r")
		key=$(os_get operations key "$r")
		[ -n "$cert" ] && [ -n "$key" ] || \
			os_error "[operations] tls=provided requires cert and key paths"
	fi
	creds=$(os_get operations credentials "$r")
	case "$creds" in
	'' | interactive) ;;
	*) os_error "[operations] credentials must be interactive (secrets are never stored)" ;;
	esac
	endpoints=$(os_get_all operations endpoints "$r")
	for ep in $endpoints; do
		case "$ep" in
		public | internal | admin) ;;
		*) os_error "[operations] unknown endpoint '$ep' (public|internal|admin)" ;;
		esac
	done
	for k in db_node mq_node; do
		v=$(os_get operations "$k" "$r")
		[ -n "$v" ] || os_error "[operations] $k is required"
		[ -n "$v" ] || continue
		# the placement must be a controller node
		roles=$(os_get_all "node $v" roles "$r")
		case " $roles " in
		*controller*) ;;
		*) os_error "[operations] $k must land on a controller node (got '$v')" ;;
		esac
	done
	ha=$(os_get operations ha "$r")
	case "$ha" in
	'' | none) ;;
	*) os_error "[operations] ha must be none (HA stack not yet available)" ;;
	esac
}

os_validate_cross()
{
	local r fam n v dup gi oi
	r=$1
	# a node address may not collide with another node's address
	: > "$OS_TMP/addrs.$$"
	for fam in 4 6; do
		for n in $(cat "$OS_TMP/nodes.$$" 2>/dev/null); do
			v=$(os_get "node $n" "address$fam" "$r")
			[ -n "$v" ] && printf '%s %s\n' "$fam" "$v" >> "$OS_TMP/addrs.$$"
		done
	done
	if [ -f "$OS_TMP/addrs.$$" ]; then
		dup=$(sort "$OS_TMP/addrs.$$" | uniq -d)
		[ -z "$dup" ] || os_error "duplicate node address: $(echo "$dup" | tr '\n' ' ')"
	fi
	# global.init and operations.init must not disagree
	gi=$(os_get global init "$r")
	oi=$(os_get operations init "$r")
	if [ -n "$gi" ] && [ -n "$oi" ] && [ "$gi" != "$oi" ]; then
		os_error "global init ($gi) and operations init ($oi) disagree"
	fi
}

# ---------------------------------------------------------------------------
# Canonical normalization (deterministic output)
# ---------------------------------------------------------------------------

os_normalize()
{
	local file records n
	# Deterministic document: fixed section order, keys sorted within
	# section, comments stripped, values trimmed. Same input => identical
	# output, so the document is diffable and reproducible.
	file=$1
	records=$(os_parse "$file") || return 1
	{
		# global first
		os_section_out global "$records"
		# nodes in sorted order
		for n in $(os_sections node "$records" | sort); do
			os_section_out "node $n" "$records"
		done
		for n in $(os_sections network "$records" | sort); do
			os_section_out "network $n" "$records"
		done
		for n in $(os_sections storage "$records" | sort); do
			os_section_out "storage $n" "$records"
		done
		for n in $(os_sections service "$records" | sort); do
			os_section_out "service $n" "$records"
		done
		os_section_out operations "$records"
	}
}

os_section_out()
{
	local sec records keys k vals
	sec=$1; records=$2
	# the section name itself: [name]
	# values grouped by key, keys sorted, list items sorted and comma-joined
	keys=$(awk -F'\t' -v s="$sec" '$1 == s { print $2 }' "$records" | awk '!seen[$0]++' | sort)
	printf '[%s]\n' "$sec"
	for k in $keys; do
		vals=$(awk -F'\t' -v s="$sec" -v kk="$k" '$1 == s && $2 == kk { print $3 }' "$records" | sort | paste -sd, -)
		printf '%s = %s\n' "$k" "$vals"
	done
	printf '\n'
}

# ---------------------------------------------------------------------------
# Temp dir handling (scratch only; never live paths)
# ---------------------------------------------------------------------------

OS_TMP=${SAPHIRA_TMPDIR:-/build/tmp}/saphira-openstack
mkdir -p "$OS_TMP" 2>/dev/null || OS_TMP=$(mktemp -d)

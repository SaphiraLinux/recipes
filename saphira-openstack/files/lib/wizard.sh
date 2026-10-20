#!/bin/sh
#
# wizard.sh - the interactive `init` wizard.
#
# The operator designs the cloud; Saphira implements it. Every convention
# here follows the firstboot wizard (saphira-firstboot):
#   * one read primitive: q/Ctrl-C = Back, EOF re-prompts, never accepts
#   * numbered menus, "(q to go back)", empty answer changes nothing
#   * no default on any choice; detected values are suggestions only
#   * validation delegated to the engine; the wizard re-implements nothing
#   * everything staged; Review is read-only; one explicit Confirm writes
#     the inventory document; Cancel writes nothing
#
# This file is sourced by the dispatcher (which calls os_wizard_main) and
# by tests (which stub wiz_read_setup and call the menu functions).
# OS_WIZARD_NO_MAIN=1 suppresses the main run on source.

# ---------------------------------------------------------------- primitives

wiz_state_dir()
{
	printf '%s\n' "${SAPHIRA_OPENSTACK_STATE_DIR:-${OS_TMP}}"
}

wiz_read_setup()
{
	# $1 = variable name to fill. q/Q = back (returns 1). EOF re-prompts.
	local variable=$1 value
	while :; do
		wiz_nav_back=
		if IFS= read -r "$variable"; then
			eval "value=\$$variable"
			case $value in
			q | Q)
				wiz_nav_back=1
				return 1
				;;
			esac
			return 0
		fi
		printf '\nEnd-of-file is not a valid setup response; please enter a value.\n' >&2
	done
}

wiz_die()
{
	printf 'saphira-openstack: wizard: %s\n' "$*" >&2
	exit 1
}

wiz_heading()
{
	printf '\n=== %s ===\n\n' "$1"
}

wiz_explain()
{
	# a sensible explanation before every menu
	printf '%s\n\n' "$1"
}

wiz_ask()
	{
	# wiz_ask <var> <prompt> <validator-fn> <errmsg>
	# Re-prompts on empty; validates via the named engine function;
	# returns 1 on back. No default is ever applied.
	var=$1; prompt=$2; validator=$3; errmsg=$4
	while :; do
		printf '%s (q to go back): ' "$prompt"
		wiz_read_setup "$var" || return 1
		eval "v=\$$var"
		case "$v" in
		'')
			printf 'An answer is required here; an empty answer changes nothing.\n' >&2
			continue
			;;
		esac
		if "$validator" "$v" >/dev/null 2>&1; then
			return 0
		fi
		printf '%s\n' "$errmsg" >&2
	done
}

wiz_menu()
{
	# wiz_menu <title> <explanation> <prompt> <option-label>...
	# Returns the chosen option's index in wiz_choice; 1-based; back = 1.
	title=$1; explain=$2; prompt=$3; shift 3
	wiz_heading "$title"
	wiz_explain "$explain"
	i=1
	for opt in "$@"; do
		printf '  [%d] %s\n' "$i" "$opt"
		i=$((i + 1))
	done
	while :; do
		printf '\n%s (q to go back): ' "$prompt"
		wiz_read_setup wiz_choice || return 1
		case "$wiz_choice" in
		'')
			printf 'Choose a number; an empty answer changes nothing.\n' >&2
			;;
		*[!0-9]* | 0)
			printf 'Choose one of the numbered options.\n' >&2
			;;
		*)
			[ "$wiz_choice" -lt "$i" ] && return 0
			printf 'Choose one of the numbered options.\n' >&2
			;;
		esac
	done
}

# ---------------------------------------------------------------- staging

# The staged document, rebuilt from accumulated answers after every change,
# so Review always shows exactly what will be written.
WIZ_DOMAIN=''
WIZ_INIT=''
WIZ_NODES=''      # "node1,node2"
WIZ_NODE_ROLES_node=''
WIZ_NODE_ADDR4_node=''
WIZ_NODE_ADDR6_node=''

	wiz_stage_write()
{
	dir=$(wiz_state_dir)
	mkdir -p "$dir"
	{
		printf '[global]\n'
		printf 'domain = %s\n' "$WIZ_DOMAIN"
		printf 'init = %s\n' "$WIZ_INIT"
		printf '\n'
		for n in $(printf '%s' "$WIZ_NODES" | tr ',' ' '); do
			[ -n "$n" ] || continue
			id=$(wiz_id "$n")
			printf '[node %s]\n' "$n"
			eval "roles=\${WIZ_NODE_ROLES_$id:-}"
			eval "a4=\${WIZ_NODE_ADDR4_$id:-}"
			eval "a6=\${WIZ_NODE_ADDR6_$id:-}"
			printf 'roles = %s\n' "$roles"
			printf 'address4 = %s\n' "$a4"
			printf 'address6 = %s\n' "$a6"
			printf '\n'
		done
		for net in $WIZ_NETS; do
			[ -n "$net" ] || continue
			wiz_stage_network "$net"
		done
		for st in $WIZ_STORAGES; do
			[ -n "$st" ] || continue
			wiz_stage_storage "$st"
		done
		for sv in $WIZ_SERVICES; do
			[ -n "$sv" ] || continue
			wiz_stage_service "$sv"
		done
		wiz_stage_operations
	} > "$dir/inventory.ini"
}

# ---------------------------------------------------------------- prefill
#
# wiz_id <section-name>: canonical variable-name suffix. Section names
# travel verbatim through WIZ_* lists and the staged document, but
# shell variables cannot contain dashes (or spaces): every dynamic
# variable interpolates wiz_id, never the raw name.

wiz_id()
{
	printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
}

# wiz_prefill <file>: load an existing validated document into every
# WIZ_* answer var, so Review shows the base document and Keep
# preserves it exactly. Fails closed on anything that does not
# validate. Field coverage mirrors wiz_stage_write one-for-one: every
# key the stage emits is restored here, or round-trips break.
# (Round-trips are proven by openstack-installer.sh section 8.)

wiz_prefill()
{
	local file records n v fam c4 c6
	file=$1
	os_validate "$file" >/dev/null || return 1
	records=$(os_parse "$file") || return 1

	WIZ_DOMAIN=$(os_get global domain "$records")
	WIZ_INIT=$(os_get global init "$records")

	# nodes (space-separated, wizard-native)
	WIZ_NODES=$(os_sections node "$records" | tr '\n' ' ')
	WIZ_NODES=${WIZ_NODES% }
	for n in $WIZ_NODES; do
		id=$(wiz_id "$n")
		eval "WIZ_NODE_ROLES_$id=\"\$(os_get_all \"node $n\" roles \"$records\" | paste -sd, -)\""
		eval "WIZ_NODE_ADDR4_$id=\"\$(os_get \"node $n\" address4 \"$records\")\""
		eval "WIZ_NODE_ADDR6_$id=\"\$(os_get \"node $n\" address6 \"$records\")\""
	done

	# networks (space-separated section names, wizard-native)
	WIZ_NETS=$(os_sections network "$records" | tr '\n' ' ')
	WIZ_NETS=${WIZ_NETS% }
	for net in $WIZ_NETS; do
		id=$(wiz_id "$net")
		eval "WIZ_NET_PURPOSE_$id=\"\$(os_get_all \"network $net\" purposes \"$records\" | paste -sd, -)\""
		eval "WIZ_NET_EXISTING_$id=\"\$(os_get \"network $net\" existing \"$records\")\""
		fam=$(os_get "network $net" family "$records")
		if [ -z "$fam" ]; then
			c4=$(os_get "network $net" cidr4 "$records")
			c6=$(os_get "network $net" cidr6 "$records")
			if [ -n "$c4" ] && [ -n "$c6" ]; then fam=dual
			elif [ -n "$c6" ]; then fam=ipv6
			else fam=ipv4
			fi
		fi
		eval "WIZ_NET_FAMILY_$id=\"$fam\""
		eval "WIZ_NET_CIDR4_$id=\"\$(os_get \"network $net\" cidr4 \"$records\")\""
		eval "WIZ_NET_GW4_$id=\"\$(os_get \"network $net\" gateway4 \"$records\")\""
		eval "WIZ_NET_MODE4_$id=\"\$(os_get \"network $net\" mode4 \"$records\")\""
		eval "WIZ_NET_CIDR6_$id=\"\$(os_get \"network $net\" cidr6 \"$records\")\""
		eval "WIZ_NET_GW6_$id=\"\$(os_get \"network $net\" gateway6 \"$records\")\""
		eval "WIZ_NET_MODE6_$id=\"\$(os_get \"network $net\" mode6 \"$records\")\""
		eval "WIZ_NET_DNS_$id=\"\$(os_get \"network $net\" dns \"$records\")\""
		eval "WIZ_NET_VLAN_$id=\"\$(os_get \"network $net\" vlan \"$records\")\""
		eval "WIZ_NET_BRIDGE_$id=\"\$(os_get \"network $net\" bridge \"$records\")\""
		eval "WIZ_NET_IFACE_$id=\"\$(os_get \"network $net\" interface \"$records\")\""
		eval "WIZ_NET_OVS_$id=\"\$(os_get \"network $net\" ovs \"$records\")\""
		eval "WIZ_NET_OWN_$id=\"\$(os_get \"network $net\" take_ownership \"$records\")\""
	done

	# storage (space-separated section names, wizard-native)
	WIZ_STORAGES=$(os_sections storage "$records" | tr '\n' ' ')
	WIZ_STORAGES=${WIZ_STORAGES% }
	for st in $WIZ_STORAGES; do
		id=$(wiz_id "$st")
		eval "WIZ_STORAGE_TYPE_$id=\"\$(os_get \"storage $st\" type \"$records\")\""
		eval "WIZ_STORAGE_SHARED_$id=\"\$(os_get \"storage $st\" shared \"$records\")\""
		eval "WIZ_STORAGE_EXISTING_$id=\"\$(os_get \"storage $st\" existing \"$records\")\""
		eval "WIZ_STORAGE_DEVICES_$id=\"\$(os_get_all \"storage $st\" devices \"$records\" | paste -sd, -)\""
	done

	# services (space-separated service names, wizard-native)
	WIZ_SERVICES=$(os_sections service "$records" | tr '\n' ' ')
	WIZ_SERVICES=${WIZ_SERVICES% }
	for sv in $WIZ_SERVICES; do
		id=$(wiz_id "$sv")
		eval "WIZ_SERVICE_NODE_$id=\"\$(os_get \"service $sv\" node \"$records\")\""
	done

	# operations
	WIZ_ENDPOINTS=$(os_get_all operations endpoints "$records" | paste -sd, -)
	WIZ_TLS=$(os_get operations tls "$records")
	WIZ_CERT=$(os_get operations cert "$records")
	WIZ_KEY=$(os_get operations key "$records")
	WIZ_CREDS=$(os_get operations credentials "$records")
	WIZ_DB_NODE=$(os_get operations db_node "$records")
	WIZ_MQ_NODE=$(os_get operations mq_node "$records")
	WIZ_HA=$(os_get operations ha "$records")

	rm -f "$records"
	WIZ_PREFILLED=1
	WIZ_FROM=$file
}

# ---------------------------------------------------------------- keep/edit

# wiz_prefilled <section>: true when --from loaded values for this
# section. The Keep/Edit gate only appears then: a fresh walk behaves
# exactly as before.
wiz_prefilled()
{
	[ -n "${WIZ_PREFILLED:-}" ] || return 1
	case $1 in
	global) [ -n "$WIZ_DOMAIN" ] ;;
	topology) [ -n "$WIZ_NODES" ] ;;
	networks) [ -n "$WIZ_NETS" ] ;;
	storage) [ -n "$WIZ_STORAGES" ] ;;
	services) [ -n "$WIZ_SERVICES" ] ;;
	operations) [ -n "$WIZ_DB_NODE" ] ;;
	*) return 1 ;;
	esac
}

# Clearing helpers: Edit means redoing the section from empty, so a
# dropped node/network/storage/service does not linger from the base
# document. (Stage iterates the WIZ_* lists only, but the lists
# themselves would otherwise accumulate.)
wiz_clear_nodes()
{
	local n id
	for n in $WIZ_NODES; do
		id=$(wiz_id "$n")
		eval "WIZ_NODE_ROLES_$id="; eval "WIZ_NODE_ADDR4_$id="; eval "WIZ_NODE_ADDR6_$id="
	done
	WIZ_NODES=''
}

wiz_clear_networks()
{
	local net id
	for net in $WIZ_NETS; do
		id=$(wiz_id "$net")
		eval "WIZ_NET_PURPOSE_$id="; eval "WIZ_NET_EXISTING_$id="
		eval "WIZ_NET_FAMILY_$id="
		eval "WIZ_NET_CIDR4_$id="; eval "WIZ_NET_GW4_$id="; eval "WIZ_NET_MODE4_$id="
		eval "WIZ_NET_CIDR6_$id="; eval "WIZ_NET_GW6_$id="; eval "WIZ_NET_MODE6_$id="
		eval "WIZ_NET_DNS_$id="
		eval "WIZ_NET_VLAN_$id="; eval "WIZ_NET_BRIDGE_$id="
		eval "WIZ_NET_IFACE_$id="; eval "WIZ_NET_OVS_$id="; eval "WIZ_NET_OWN_$id="
	done
	WIZ_NETS=''
}

wiz_clear_storages()
{
	local st id
	for st in $WIZ_STORAGES; do
		id=$(wiz_id "$st")
		eval "WIZ_STORAGE_TYPE_$id="; eval "WIZ_STORAGE_SHARED_$id="
		eval "WIZ_STORAGE_EXISTING_$id="; eval "WIZ_STORAGE_DEVICES_$id="
	done
	WIZ_STORAGES=''
}

wiz_clear_services()
{
	local sv id
	for sv in $WIZ_SERVICES; do
		id=$(wiz_id "$sv")
		eval "WIZ_SERVICE_NODE_$id="
	done
	WIZ_SERVICES=''
}

# Compact one-line-per-item summaries, from WIZ_* state, for the
# Keep/Edit prompts.
wiz_show_global()
{
	printf '  domain = %s\n  init   = %s\n' "$WIZ_DOMAIN" "$WIZ_INIT"
}

wiz_show_topology()
{
	local n id
	for n in $WIZ_NODES; do
		id=$(wiz_id "$n")
		printf '  node %s roles=%s' "$n" "$(eval "echo \${WIZ_NODE_ROLES_$id:-}")"
		printf ' address4=%s' "$(eval "echo \${WIZ_NODE_ADDR4_$id:-}")"
		printf ' address6=%s\n' "$(eval "echo \${WIZ_NODE_ADDR6_$id:-}")"
	done
}

wiz_show_networks()
{
	local net id
	for net in $WIZ_NETS; do
		id=$(wiz_id "$net")
		printf '  [network %s]\n' "$net"
		printf '    purposes=%s existing=%s family=%s\n' \
			"$(eval "echo \${WIZ_NET_PURPOSE_$id:-}")" \
			"$(eval "echo \${WIZ_NET_EXISTING_$id:-}")" \
			"$(eval "echo \${WIZ_NET_FAMILY_$id:-}")"
		for fam in 4 6; do
			cidr=$(eval "echo \${WIZ_NET_CIDR${fam}_$id:-}")
			[ -n "$cidr" ] || continue
			printf '    cidr%s=%s gateway%s=%s mode%s=%s\n' "$fam" "$cidr" "$fam" \
				"$(eval "echo \${WIZ_NET_GW${fam}_$id:-}")" "$fam" \
				"$(eval "echo \${WIZ_NET_MODE${fam}_$id:-}")"
		done
		printf '    dns=%s vlan=%s bridge=%s interface=%s ovs=%s take_ownership=%s\n' \
			"$(eval "echo \${WIZ_NET_DNS_$id:-}")" \
			"$(eval "echo \${WIZ_NET_VLAN_$id:-}")" \
			"$(eval "echo \${WIZ_NET_BRIDGE_$id:-}")" \
			"$(eval "echo \${WIZ_NET_IFACE_$id:-}")" \
			"$(eval "echo \${WIZ_NET_OVS_$id:-}")" \
			"$(eval "echo \${WIZ_NET_OWN_$id:-}")"
	done
}

wiz_show_storages()
{
	local st id
	for st in $WIZ_STORAGES; do
		id=$(wiz_id "$st")
		printf '  [storage %s] type=%s shared=%s existing=%s devices=%s\n' "$st" \
			"$(eval "echo \${WIZ_STORAGE_TYPE_$id:-}")" \
			"$(eval "echo \${WIZ_STORAGE_SHARED_$id:-}")" \
			"$(eval "echo \${WIZ_STORAGE_EXISTING_$id:-}")" \
			"$(eval "echo \${WIZ_STORAGE_DEVICES_$id:-}")"
	done
}

wiz_show_services()
{
	local sv id
	for sv in $WIZ_SERVICES; do
		id=$(wiz_id "$sv")
		printf '  service %s node=%s\n' "$sv" "$(eval "echo \${WIZ_SERVICE_NODE_$id:-}")"
	done
}

wiz_show_operations()
{
	printf '  init=%s endpoints=%s tls=%s credentials=%s\n' \
		"$WIZ_INIT" "${WIZ_ENDPOINTS:-public,internal,admin}" \
		"${WIZ_TLS:-none}" "${WIZ_CREDS:-interactive}"
	printf '  db_node=%s mq_node=%s ha=%s\n' \
		"$WIZ_DB_NODE" "$WIZ_MQ_NODE" "${WIZ_HA:-none}"
}

# ---------------------------------------------------------------- global

menu_global()
{
	if wiz_prefilled global; then
		wiz_heading 'Global settings (from existing document)'
		wiz_explain 'These values came from your existing document. They are preserved unless you change them.'
		wiz_show_global
		wiz_menu KeepGlobal 'Keep the existing values, or change them.' 'Keep or change?' \
			'Keep these values' 'Change them'
		[ "$wiz_choice" = 1 ] && return 0
	fi
	wiz_ask WIZ_DOMAIN 'Domain name for this cloud (e.g. cloud.example)' \
		os_valid_dns 'That is not a valid DNS name.' || return 1
	case "$WIZ_DOMAIN" in
	*.*) ;;
	*) printf 'A domain should contain at least one dot (e.g. cloud.example).\n' >&2
		return 1
		;;
	esac
	wiz_menu InitSystem \
		'Every long-running OpenStack service needs an init system. Saphira ships both; the operator chooses which one is active. Nothing is auto-enabled.' \
		'Choose the init system' \
		'OpenRC' 'systemd'
	case "$wiz_choice" in
	1) WIZ_INIT=openrc ;;
	2) WIZ_INIT=systemd ;;
	esac
}

# ---------------------------------------------------------------- topology

menu_topology()
{
	if wiz_prefilled topology; then
		wiz_heading 'Topology (from existing document)'
		wiz_explain 'These machines came from your existing document. They are preserved unless you change them.'
		wiz_show_topology
		wiz_menu KeepTopology 'Keep the existing machines, or change them.' 'Keep or change?' \
			'Keep these machines' 'Change machines'
		if [ "$wiz_choice" = 1 ]; then return 0; fi
		wiz_clear_nodes
	fi
	wiz_menu Topology \
		'Choose how many machines make up this cloud. Single-node puts every role on one machine; multi-node lets you spread roles across several. Any number of machines, any roles per machine.' \
		'Topology' \
		'Single-node (all roles on one machine)' 'Multi-node (several machines)'
	case "$wiz_choice" in
	1) wiz_topology_single ;;
	2) wiz_topology_multi ;;
	esac
}

wiz_topology_single()
{
	WIZ_NODES=controller
	ask_node_roles controller
	wiz_ask WIZ_NODE_ADDR4_controller 'Management IPv4 address for controller (optional, press q to skip)' \
		os_valid_addr4 'That is not a valid IPv4 address.' || {
		# back on optional address: leave it empty
		WIZ_NODE_ADDR4_controller=
	}
	wiz_ask WIZ_NODE_ADDR6_controller 'Management IPv6 address for controller (optional)' \
		os_valid_addr6 'That is not a valid IPv6 address.' || {
		WIZ_NODE_ADDR6_controller=
	}
}

wiz_topology_multi()
{
	count=0
	while :; do
		count=$((count + 1))
		wiz_ask name "Hostname for machine $count (q to finish adding machines)" \
			os_valid_name 'That is not a valid hostname.' || {
			count=$((count - 1))
			break
		}
		case " $WIZ_NODES " in
		*" $name "*) printf 'A machine named %s already exists.\n' "$name" >&2
			count=$((count - 1))
			continue
			;;
		esac
		WIZ_NODES="${WIZ_NODES:+$WIZ_NODES }$name"
		ask_node_roles "$name"
		id=$(wiz_id "$name")
		wiz_ask "WIZ_NODE_ADDR4_$id" "Management IPv4 for $name (q to skip)" \
			os_valid_addr4 'That is not a valid IPv4 address.' || eval "WIZ_NODE_ADDR4_$id="
		wiz_ask "WIZ_NODE_ADDR6_$id" "Management IPv6 for $name (q to skip)" \
			os_valid_addr6 'That is not a valid IPv6 address.' || eval "WIZ_NODE_ADDR6_$id="
		[ "$count" -ge 2 ] && {
			wiz_menu AddMore "Add another machine?" 'Add another?' \
				'Yes, add another machine' 'No, that is all'
			[ "$wiz_choice" = 1 ] || break
		}
	done
	[ -n "$WIZ_NODES" ] || { printf 'At least one machine is required.\n' >&2; return 1; }
}

ask_node_roles()
{
	node=$1
	id=$(wiz_id "$node")
	wiz_explain 'Choose the roles for this machine. A controller runs the control plane (identity, APIs, databases). A compute runs virtual machines. A machine may hold both roles.'
	wiz_menu "Roles for $node" 'Pick one or more roles.' \
		'Choose the roles for this machine' \
		'Controller (control plane)' 'Compute (run virtual machines)' \
		'Both controller and compute'
	case "$wiz_choice" in
	1) eval "WIZ_NODE_ROLES_$id=controller" ;;
	2) eval "WIZ_NODE_ROLES_$id=compute" ;;
	3) eval "WIZ_NODE_ROLES_$id=controller,compute" ;;
	esac
}

# ---------------------------------------------------------------- networking

WIZ_NETS=''
wiz_net_purpose_vars()
{
	local _id
	_id=$(wiz_id "$1")
	eval "purp=\${WIZ_NET_PURPOSE_$_id:-}"
	eval "existing=\${WIZ_NET_EXISTING_$_id:-}"
	eval "family=\${WIZ_NET_FAMILY_$_id:-}"
	eval "cidr4=\${WIZ_NET_CIDR4_$_id:-}"
	eval "gw4=\${WIZ_NET_GW4_$_id:-}"
	eval "mode4=\${WIZ_NET_MODE4_$_id:-}"
	eval "cidr6=\${WIZ_NET_CIDR6_$_id:-}"
	eval "gw6=\${WIZ_NET_GW6_$_id:-}"
	eval "mode6=\${WIZ_NET_MODE6_$_id:-}"
	eval "dns=\${WIZ_NET_DNS_$_id:-}"
	eval "vlan=\${WIZ_NET_VLAN_$_id:-}"
	eval "bridge=\${WIZ_NET_BRIDGE_$_id:-}"
	eval "iface=\${WIZ_NET_IFACE_$_id:-}"
	eval "ovs=\${WIZ_NET_OVS_$_id:-}"
	eval "own=\${WIZ_NET_OWN_$_id:-}"
}

wiz_stage_network()
{
	net=$1
	wiz_net_purpose_vars "$net"
	# a wizard network section is named after its purpose, so purposes
	# defaults to the section name (hand-written inventories may list
	# several purposes; the engine accepts that)
	eval "purp=\${WIZ_NET_PURPOSE_$(wiz_id "$net"):-$net}"
	printf '[network %s]\n' "$net"
	printf 'purposes = %s\n' "$purp"
	printf 'existing = %s\n' "$existing"
	printf 'family = %s\n' "$family"
	[ -n "$cidr4" ] && printf 'cidr4 = %s\n' "$cidr4"
	[ -n "$gw4" ] && printf 'gateway4 = %s\n' "$gw4"
	[ -n "$mode4" ] && printf 'mode4 = %s\n' "$mode4"
	[ -n "$cidr6" ] && printf 'cidr6 = %s\n' "$cidr6"
	[ -n "$gw6" ] && printf 'gateway6 = %s\n' "$gw6"
	[ -n "$mode6" ] && printf 'mode6 = %s\n' "$mode6"
	[ -n "$dns" ] && printf 'dns = %s\n' "$dns"
	[ -n "$vlan" ] && printf 'vlan = %s\n' "$vlan"
	[ -n "$bridge" ] && printf 'bridge = %s\n' "$bridge"
	[ -n "$iface" ] && printf 'interface = %s\n' "$iface"
	[ -n "$ovs" ] && printf 'ovs = %s\n' "$ovs"
	[ -n "$own" ] && printf 'take_ownership = %s\n' "$own"
	printf '\n'
}

menu_networks()
{
	if wiz_prefilled networks; then
		wiz_heading 'Networks (from existing document)'
		wiz_explain 'These networks came from your existing document. They are preserved unless you change them.'
		wiz_show_networks
		wiz_menu KeepNetworks 'Keep the existing networks, or change them.' 'Keep or change?' \
			'Keep these networks' 'Change networks'
		if [ "$wiz_choice" = 1 ]; then return 0; fi
		wiz_clear_networks
	fi
	wiz_menu NetworkPurposes \
		'Choose which networks this cloud needs. Management is required: it carries API and control traffic. Provider/external connects to the outside world. Tenant/overlay carries instance traffic. Storage carries storage traffic. One network may serve several purposes.' \
		'Which networks do you need?' \
		'Management only' \
		'Management + provider/external' \
		'Management + tenant/overlay' \
		'Management + storage' \
		'All four' \
		'Custom selection'
	case "$wiz_choice" in
	1) WIZ_NETS="management" ;;
	2) WIZ_NETS="management provider" ;;
	3) WIZ_NETS="management tenant" ;;
	4) WIZ_NETS="management storage" ;;
	5) WIZ_NETS="management provider tenant storage" ;;
	6) wiz_net_custom_purposes ;;
	esac
	[ -n "$WIZ_NETS" ] || WIZ_NETS=management
	for net in $WIZ_NETS; do
		wiz_net_configure "$net" || return 1
	done
}

wiz_net_custom_purposes()
{
	# multi-select by number: "1,2,3"
	printf 'Select purposes by number, comma-separated (management is required):\n'
	printf '  [1] management  [2] provider  [3] tenant  [4] storage\n'
	wiz_ask pick 'Your selection' os_valid_csv 'Enter numbers like 1,3.' || return 1
	WIZ_NETS=management
	case "$pick" in
	*2*) WIZ_NETS="$WIZ_NETS provider" ;;
	esac
	case "$pick" in
	*3*) WIZ_NETS="$WIZ_NETS tenant" ;;
	esac
	case "$pick" in
	*4*) WIZ_NETS="$WIZ_NETS storage" ;;
	esac
}

wiz_net_configure()
{
	net=$1

	id=$(wiz_id "$net")
	wiz_menu "Network: $net" \
		"Configure the $net network. You may create a new network or reference an existing one. Nothing is created or changed here." \
		'Is this a new network or an existing one?' \
		'New network' 'Existing network (use as-is)'
	case "$wiz_choice" in
	1) eval "WIZ_NET_EXISTING_$id=no" ;;
	2) eval "WIZ_NET_EXISTING_$id=yes" ;;
	esac
	eval "existing=\${WIZ_NET_EXISTING_$id:-}"
	if [ "$existing" = yes ]; then
		wiz_net_existing "$net"
		return 0
	fi
	wiz_net_new "$net"
}

wiz_net_existing()
{
	net=$1

	id=$(wiz_id "$net")
	printf '# detected interfaces and bridges (read-only suggestions; confirm each):\n'
	os_detect interfaces
	os_detect ovs
	wiz_ask "WIZ_NET_IFACE_$id" 'Name of the existing interface or bridge to use' \
		os_valid_name 'That is not a valid name.' || return 1
	# adopting an existing interface requires explicit approval
	wiz_menu TakeOwnership \
		'Taking ownership of an existing interface means Saphira will manage it. Say yes only if you approve.' \
		'Do you approve taking ownership?' \
		'No, reference it only (default)' 'Yes, Saphira may manage it'
	case "$wiz_choice" in
	1) eval "WIZ_NET_OWN_$id=no" ;;
	2) eval "WIZ_NET_OWN_$id=yes" ;;
	esac
}

wiz_net_new()
{
	net=$1

	id=$(wiz_id "$net")
	wiz_menu "Family for $net" \
		'IPv4 and IPv6 are independent. Choose which families this network carries. Any combination is valid.' \
		'Address families' \
		'IPv4 only' 'IPv6 only' 'Dual-stack (IPv4 and IPv6)'
	case "$wiz_choice" in
	1) eval "WIZ_NET_FAMILY_$id=ipv4" ;;
	2) eval "WIZ_NET_FAMILY_$id=ipv6" ;;
	3) eval "WIZ_NET_FAMILY_$id=dual" ;;
	esac
	eval "family=\${WIZ_NET_FAMILY_$id:-}"
	for fam in 4 6; do
		[ "$family" = ipv4 ] && [ "$fam" = 6 ] && continue
		[ "$family" = ipv6 ] && [ "$fam" = 4 ] && continue
		wiz_net_family "$net" "$fam" || return 1
	done
	wiz_net_common "$net"
}

wiz_net_family()
{
	net=$1; fam=$2

	id=$(wiz_id "$net")
	wiz_menu "Addressing for $net (IPv$fam)" \
		'Choose how addresses on this network are assigned. Static requires a CIDR you choose; any subnet is accepted.' \
		'IPv$fam addressing mode' \
		'Static (choose addresses)' 'DHCP' 'None (this family is not used)'
	case "$wiz_choice" in
	1)
		wiz_ask "WIZ_NET_CIDR${fam}_$net" "IPv$fam CIDR (e.g. 192.0.2.0/24 or 2001:db8:1::/64)" \
			"os_valid_cidr$fam" "That is not a valid IPv$fam CIDR." || return 1
		wiz_ask "WIZ_NET_GW${fam}_$net" "IPv$fam gateway (optional, q to skip)" \
			"os_valid_addr$fam" 'That is not a valid address.' || eval "WIZ_NET_GW${fam}_$net="
		eval "cidr=\${WIZ_NET_CIDR${fam}_$net:-}"
		eval "gw=\${WIZ_NET_GW${fam}_$net:-}"
		if [ -n "$gw" ]; then
			"os_gateway_in_cidr$fam" "$cidr" "$gw" >/dev/null 2>&1 || {
				printf 'Gateway %s is not inside %s.\n' "$gw" "$cidr" >&2
				return 1
			}
		fi
		eval "WIZ_NET_MODE${fam}_$net=static"
		;;
	2) eval "WIZ_NET_MODE${fam}_$net=dhcp" ;;
	3) eval "WIZ_NET_MODE${fam}_$net=none" ;;
	esac
	wiz_ask "WIZ_NET_DNS_$id" "DNS server for $net (optional, q to skip)" \
		os_valid_dns 'That is not a valid DNS entry.' || eval "WIZ_NET_DNS_$id="
}

wiz_net_common()
{
	net=$1

	id=$(wiz_id "$net")
	wiz_ask "WIZ_NET_VLAN_$id" 'VLAN id (1-4094, optional, q to skip)' \
		os_valid_vlan 'VLAN must be 1-4094.' || eval "WIZ_NET_VLAN_$id="
	wiz_ask "WIZ_NET_BRIDGE_$id" 'Bridge name (optional, q to skip)' \
		os_valid_name 'That is not a valid name.' || eval "WIZ_NET_BRIDGE_$id="
	wiz_ask "WIZ_NET_OVS_$id" 'OVS mapping bridge:port (optional, q to skip)' \
		os_valid_ovsmap 'OVS mapping must be bridge:port.' || eval "WIZ_NET_OVS_$id="
	eval "iface=\${WIZ_NET_IFACE_$id:-}"
	if [ -z "$iface" ]; then
		printf '# detected interfaces (read-only suggestions; confirm each):\n'
		os_detect interfaces
		wiz_ask "WIZ_NET_IFACE_$id" 'Physical interface for this network (optional, q to skip)' \
			os_valid_name 'That is not a valid name.' || eval "WIZ_NET_IFACE_$id="
		eval "iface=\${WIZ_NET_IFACE_$id:-}"
		if [ -n "$iface" ] && [ -d "/sys/class/net/$iface" ]; then
			wiz_menu TakeOwnership \
				"$iface exists on this machine. Taking ownership means Saphira will manage it." \
				'Do you approve taking ownership?' \
				'No, reference it only (default)' 'Yes, Saphira may manage it'
			case "$wiz_choice" in
			1) eval "WIZ_NET_OWN_$id=no" ;;
			2) eval "WIZ_NET_OWN_$id=yes" ;;
			esac
		fi
	fi
}

# ---------------------------------------------------------------- storage

WIZ_STORAGES=''
wiz_stage_storage()
{
	st=$1
	id=$(wiz_id "$st")
	eval "type=\${WIZ_STORAGE_TYPE_$id:-}"
	eval "shared=\${WIZ_STORAGE_SHARED_$id:-}"
	eval "existing=\${WIZ_STORAGE_EXISTING_$id:-}"
	printf '[storage %s]\n' "$st"
	printf 'type = %s\n' "$type"
	printf 'shared = %s\n' "$shared"
	printf 'existing = %s\n' "$existing"
	eval "devs=\${WIZ_STORAGE_DEVICES_$id:-}"
	[ -n "$devs" ] && printf 'devices = %s\n' "$devs"
	printf '\n'
}

menu_storage()
{
	if wiz_prefilled storage; then
		wiz_heading 'Storage (from existing document)'
		wiz_explain 'This storage came from your existing document. It is preserved unless you change it.'
		wiz_show_storages
		wiz_menu KeepStorage 'Keep the existing storage, or change it.' 'Keep or change?' \
			'Keep this storage' 'Change storage'
		if [ "$wiz_choice" = 1 ]; then return 0; fi
		wiz_clear_storages
	fi
	wiz_menu Storage \
		'Configure storage backends. You may create new storage or use existing pools, datasets and shares as-is. Nothing is formatted, created or destroyed here.' \
		'How much storage do you need to configure?' \
		'One storage backend' 'Several storage backends' 'Skip storage for now'
	case "$wiz_choice" in
	1) wiz_storage_configure storage1 ;;
	2)
		wiz_storage_configure storage1 || return 1
		wiz_storage_configure storage2 || return 1
		;;
	3) ;;
	esac
	[ -n "$WIZ_STORAGES" ] || WIZ_STORAGES=''
}

wiz_storage_configure()
{
	st=$1

	id=$(wiz_id "$st")
	wiz_menu "Storage: $st" \
		'Choose the backend type. ZFS is native to Saphira; local and NFS are ready. LVM and Ceph are pending.' \
		'Backend type' \
		'ZFS pool' 'ZFS dataset' 'Local directory' 'NFS share' \
		'LVM (pending)' 'Ceph (pending)'
	case "$wiz_choice" in
	1) type=zfs-pool ;;
	2) type=zfs-dataset ;;
	3) type=local ;;
	4) type=nfs ;;
	5) type=lvm ;;
	6) type=ceph ;;
	esac
	eval "WIZ_STORAGE_TYPE_$id=$type"
	wiz_ask "WIZ_STORAGE_NAME_$id" 'Name for this storage (pool, dataset, directory or share)' \
		os_valid_name 'That is not a valid name.' || return 1
	wiz_menu ExistingStorage \
		'Use existing storage as-is, or create new? Existing storage is only imported or attached, never recreated, formatted or destroyed.' \
		'Is this existing storage?' \
		'New storage' 'Existing storage (use as-is)'
	case "$wiz_choice" in
	1) eval "WIZ_STORAGE_EXISTING_$id=no" ;;
	2) eval "WIZ_STORAGE_EXISTING_$id=yes" ;;
	esac
	eval "existing=\${WIZ_STORAGE_EXISTING_$id:-}"
	case "$type" in
	zfs-pool)
		if [ "$existing" = yes ]; then
			printf '# detected ZFS pools (read-only suggestions; confirm each):\n'
			os_detect zfs
			wiz_explain 'An existing pool will only be imported/attached, never recreated.'
		else
			wiz_ask "WIZ_STORAGE_DEVICES_$id" 'Devices for the new pool (comma-separated, e.g. /dev/sdb,/dev/sdc)' \
				os_valid_name 'Device names required.' || eval "WIZ_STORAGE_DEVICES_$id="
		fi
		;;
	zfs-dataset)
		printf '# detected ZFS datasets (read-only suggestions; confirm each):\n'
		os_detect zfs
		;;
	esac
	wiz_menu SharedStorage 'Is this storage shared across machines?' 'Shared?' \
		'No, local to one machine' 'Yes, shared'
	case "$wiz_choice" in
	1) eval "WIZ_STORAGE_SHARED_$id=no" ;;
	2) eval "WIZ_STORAGE_SHARED_$id=yes" ;;
	esac
	WIZ_STORAGES="${WIZ_STORAGES:+$WIZ_STORAGES }$st"
}

# ---------------------------------------------------------------- services

WIZ_SERVICES=''
wiz_stage_service()
{
	sv=$1
	eval "node=\${WIZ_SERVICE_NODE_$(wiz_id "$sv"):-}"
	printf '[service %s]\n' "$sv"
	printf 'node = %s\n' "$node"
	printf '\n'
}

menu_services()
{
	if wiz_prefilled services; then
		wiz_heading 'Services (from existing document)'
		wiz_explain 'These service placements came from your existing document. They are preserved unless you change them. Keystone (identity) is required by everything.'
		wiz_show_services
		wiz_menu KeepServices 'Keep the existing services, or change them.' 'Keep or change?' \
			'Keep these services' 'Change services'
		if [ "$wiz_choice" = 1 ]; then return 0; fi
		wiz_clear_services
	fi
	printf '# catalog services (readiness is probed at plan time):\n'
	os_catalog_list services
	wiz_explain 'Select the OpenStack components you need. Keystone (identity) is required by everything. Dependencies are shown; the planner enforces them. Nothing here is installed.'
	printf 'Select services by name, comma-separated (e.g. keystone,glance,nova):\n'
	wiz_ask pick 'Services' os_valid_csv 'Enter service names.' || return 1
	for sv in $(printf '%s' "$pick" | tr ',' ' '); do
		id=$(wiz_id "$sv")
		row=$(os_catalog_rows services | awk -F'|' -v n="$sv" '$1 == n')
		[ -n "$row" ] || {
			printf 'Unknown service: %s\n' "$sv" >&2
			return 1
		}
		deps=$(printf '%s\n' "$row" | awk -F'|' '{ print $3 }')
		printf '  %s depends on: %s\n' "$sv" "$deps"
		wiz_ask "WIZ_SERVICE_NODE_$id" "Node for $sv (a machine with a matching role)" \
			os_valid_name 'That is not a valid name.' || return 1
		case " $WIZ_NODES " in
		*" $(eval "echo \$WIZ_SERVICE_NODE_$id") "*) ;;
		*) printf 'Node %s is not in the inventory.\n' "$(eval "echo \$WIZ_SERVICE_NODE_$id")" >&2
			return 1
			;;
		esac
		WIZ_SERVICES="${WIZ_SERVICES:+$WIZ_SERVICES }$sv"
	done
	case " $WIZ_SERVICES " in
	*keystone*) ;;
	*) printf 'keystone is required: every OpenStack service depends on identity.\n' >&2
		return 1
		;;
	esac
}

# ---------------------------------------------------------------- operations

wiz_stage_operations()
{
	printf '[operations]\n'
	printf 'init = %s\n' "$WIZ_INIT"
	# optional keys are written only when chosen: an absent key and
	# an explicit default must round-trip identically, so --from
	# never materializes defaults the operator did not write
	[ -n "${WIZ_ENDPOINTS:-}" ] && printf 'endpoints = %s\n' "$WIZ_ENDPOINTS"
	[ -n "${WIZ_TLS:-}" ] && printf 'tls = %s\n' "$WIZ_TLS"
	[ "${WIZ_TLS:-none}" = provided ] && {
		printf 'cert = %s\n' "${WIZ_CERT:-}"
		printf 'key = %s\n' "${WIZ_KEY:-}"
	}
	[ -n "${WIZ_CREDS:-}" ] && printf 'credentials = %s\n' "$WIZ_CREDS"
	printf 'db_node = %s\n' "${WIZ_DB_NODE:-}"
	printf 'mq_node = %s\n' "${WIZ_MQ_NODE:-}"
	[ -n "${WIZ_HA:-}" ] && printf 'ha = %s\n' "$WIZ_HA"
	printf '\n'
}

menu_operations()
{
	if wiz_prefilled operations; then
		wiz_heading 'Operations (from existing document)'
		wiz_explain 'These operational choices came from your existing document. They are preserved unless you change them.'
		wiz_show_operations
		wiz_menu KeepOperations 'Keep the existing choices, or change them.' 'Keep or change?' \
			'Keep these choices' 'Change operations'
		[ "$wiz_choice" = 1 ] && return 0
	fi
	wiz_menu Endpoints \
		'API endpoints expose the cloud APIs. Choose which endpoint types to serve.' \
		'Endpoints' \
		'public,internal,admin (all)' 'public only' 'Custom selection'
	case "$wiz_choice" in
	1) WIZ_ENDPOINTS="public,internal,admin" ;;
	2) WIZ_ENDPOINTS="public" ;;
	3)
		printf 'Select endpoints by number: [1] public [2] internal [3] admin\n'
		wiz_ask pick 'Endpoints' os_valid_csv 'Enter numbers like 1,3.' || return 1
		WIZ_ENDPOINTS=
		case "$pick" in
		*1*) WIZ_ENDPOINTS="public" ;;
		esac
		case "$pick" in
		*2*) WIZ_ENDPOINTS="${WIZ_ENDPOINTS:+$WIZ_ENDPOINTS,}internal" ;;
		esac
		case "$pick" in
		*3*) WIZ_ENDPOINTS="${WIZ_ENDPOINTS:+$WIZ_ENDPOINTS,}admin" ;;
		esac
		[ -n "$WIZ_ENDPOINTS" ] || WIZ_ENDPOINTS=public
		;;
	esac
	wiz_menu TLS \
		'TLS protects API traffic. None is for trusted networks only. Selfsigned generates certificates at apply time. Provided uses certificates you supply.' \
		'TLS mode' \
		'None' 'Selfsigned (generated at apply time)' 'Provided (you supply cert and key)'
	case "$wiz_choice" in
	1) WIZ_TLS=none ;;
	2) WIZ_TLS=selfsigned ;;
	3)
		WIZ_TLS=provided
		wiz_ask WIZ_CERT 'Path to the certificate file' os_valid_name 'Enter a path.' || return 1
		wiz_ask WIZ_KEY 'Path to the key file' os_valid_name 'Enter a path.' || return 1
		;;
	esac
	wiz_menu Credentials \
		'Admin credentials are prompted when the configuration is applied, never stored in the inventory document.' \
		'Credential handling' \
		'Interactive (prompt at apply time; secrets never stored)'
	WIZ_CREDS=interactive
	# placement of database and message queue on controller nodes
	for k in db_node mq_node; do
		wiz_ask "WIZ_$(echo "$k" | tr 'a-z' 'A-Z')" "Node for the $k (a controller machine)" \
			os_valid_name 'That is not a valid name.' || return 1
		case " $WIZ_NODES " in
		*" $(eval "echo \$WIZ_$(echo "$k" | tr 'a-z' 'A-Z')") "*) ;;
		*) printf 'Node %s is not in the inventory.\n' "$(eval "echo \$WIZ_$(echo "$k" | tr 'a-z' 'A-Z')")" >&2
			return 1
			;;
		esac
	done
	wiz_menu HA \
		'High availability settings. The HA stack is not yet available; the option is recorded for when it lands.' \
		'HA mode' \
		'None (single controller)' 'HA (pending)'
	case "$wiz_choice" in
	1) WIZ_HA=none ;;
	2) WIZ_HA=none
		printf 'HA is not yet available; recorded as pending.\n' >&2
		;;
	esac
}

# ---------------------------------------------------------------- review

menu_review()
{
	wiz_stage_write
	wiz_heading Review
	wiz_explain 'This is the inventory document that would be written. Review it; go back to change anything, or confirm to write it. Nothing is applied.'
	printf '%s\n' '-----'
	cat "$(wiz_state_dir)/inventory.ini"
	printf '%s\n' '-----'
	# validate the staged document through the engine before offering confirm
	if ! os_validate "$(wiz_state_dir)/inventory.ini" >/dev/null 2>&1; then
		printf 'The staged configuration does not validate:\n' >&2
		os_validate "$(wiz_state_dir)/inventory.ini" 2>&2 || true
		return 1
	fi
	wiz_menu Confirm \
		'Write this inventory document? It does not install or configure anything.' \
		'Write this inventory document?' \
		'Confirm and write' 'No, go back and edit' 'Cancel (write nothing)'
	case "$wiz_choice" in
	1) return 0 ;;
	2) return 2 ;;
	3) return 3 ;;
	esac
}

# ---------------------------------------------------------------- main

os_wizard_main()
{
	from=''
	output=''
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--from) from=$2; shift 2 ;;
		--output) output=$2; shift 2 ;;
		*) die "unknown init option: $1" ;;
		esac
	done

	wiz_heading 'Saphira OpenStack'
	wiz_explain 'Design your own cloud. You make every decision; Saphira implements them. Nothing here installs or configures anything. You can go back at any prompt (q), review before anything is written, and cancel without writing.'

	# load an existing document as the editable base: every choice is
	# restored into the wizard state, Review shows the base, and each
	# section offers Keep (byte-identical) or Change (redo that
	# section from empty). Fails closed on invalid documents.
	if [ -n "$from" ]; then
		[ -f "$from" ] || die "source document not found: $from"
		wiz_prefill "$from" || die "source document does not validate: $from"
	fi

	# step machine: each returns 0 next, 1 back, 2 edit, 3 cancel
	step=0
	rc=0
	while :; do
		rc=0
		case $step in
		0) menu_global || rc=$? ;;
		1) menu_topology || rc=$? ;;
		2) menu_networks || rc=$? ;;
		3) menu_storage || rc=$? ;;
		4) menu_services || rc=$? ;;
		5) menu_operations || rc=$? ;;
		6) menu_review || rc=$? ;;
		esac
		case $rc in
		0) step=$((step + 1)) ;;
		1)
			[ "$step" -gt 0 ] && step=$((step - 1))
			;;
		2) ;;
		3)
			printf 'Cancelled. Nothing was written.\n'
			exit 0
			;;
		*) step=$((step + 1)) ;;
		esac
		[ "$step" -gt 6 ] && break
	done

	# step 6 returned 0 from review: write the document
	target=${output:-/etc/saphira-openstack/inventory.ini}
	printf 'Writing inventory document: %s\n' "$target"
	mkdir -p "$(dirname "$target")"
	cp "$(wiz_state_dir)/inventory.ini" "$target"
	printf 'Done. Inspect it with: saphira-openstack inventory --file %s\n' "$target"
	printf 'Plan it with:       saphira-openstack plan --file %s\n' "$target"
	printf 'Nothing has been installed or configured.\n'
}

# sourced: do not auto-run
if [ "${OS_WIZARD_NO_MAIN:-}" != 1 ]; then
	os_wizard_main "$@"
fi

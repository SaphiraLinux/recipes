#!/bin/sh
#
# plan.sh - the `plan` interface: display exactly what would be installed
# or changed, without changing the system. Read-only unless --out DIR is
# given explicitly, and even then only plan files are written there.

os_plan_render()
{
	local file out records plan
	file=$1
	out=$2
	os_reset_errors
	records=$(os_parse "$file") || { os_error "document does not parse"; return 1; }
	os_validate "$file" || return 1

	plan=$(os_plan_build "$records" "$file")
	if [ -n "$out" ]; then
		# the ONLY write path: create the directory, write plan files
		# inside it, and refuse anything that already exists at a live path
		case "$out" in
		/etc | /var | /usr | /bin | /sbin | /lib | /opt | /)
			die "refusing --out at a live system path: $out"
			;;
		esac
		mkdir -p "$out" || die "cannot create plan directory: $out"
		printf '%s\n' "$plan" > "$out/plan.txt"
		printf '%s\n' "$(os_normalize "$file")" > "$out/inventory.ini"
		printf 'saphira-openstack: plan written to %s/plan.txt\n' "$out"
		return 0
	fi
	printf '%s\n' "$plan"
}

os_plan_build()
{
	local r file plan_id
	r=$1
	file=$2
	plan_id=$(os_normalize "$file" | sha256sum | awk '{ print $1 }')

	{
		printf '# saphira-openstack plan\n'
		printf '# source: %s\n' "$file"
		printf '# plan_id: %s\n' "$plan_id"
		# no timestamps: the same document always yields the same plan
		printf '\n'

		os_plan_topology "$r"
		os_plan_networks "$r"
		os_plan_storage "$r"
		os_plan_services "$r"
		os_plan_operations "$r"
		os_plan_integration "$r"
	} || return 1
}

os_plan_topology()
{
	local r nodes n
	r=$1
	printf '## topology\n'
	nodes=$(os_sections node "$r" | sort)
	for n in $nodes; do
		printf 'node %s\n' "$n"
		printf '  roles: %s\n' "$(os_get_all "node $n" roles "$r" | paste -sd, -)"
		printf '  address4: %s\n' "$(os_get "node $n" address4 "$r")"
		printf '  address6: %s\n' "$(os_get "node $n" address6 "$r")"
	done
	printf '\n'
}

os_plan_networks()
{
	local r nets net fam cidr k v
	r=$1
	printf '## networks\n'
	nets=$(os_sections network "$r" | sort)
	for net in $nets; do
		printf 'network %s\n' "$net"
		printf '  purposes: %s\n' "$(os_get_all "network $net" purposes "$r" | paste -sd, -)"
		printf '  existing: %s\n' "$(os_get "network $net" existing "$r")"
		for fam in 4 6; do
			cidr=$(os_get "network $net" "cidr$fam" "$r")
			[ -n "$cidr" ] || continue
			printf '  cidr%s: %s\n' "$fam" "$cidr"
			[ -n "$(os_get "network $net" "gateway$fam" "$r")" ] && \
				printf '  gateway%s: %s\n' "$fam" "$(os_get "network $net" "gateway$fam" "$r")"
			[ -n "$(os_get "network $net" "mode$fam" "$r")" ] && \
				printf '  mode%s: %s\n' "$fam" "$(os_get "network $net" "mode$fam" "$r")"
		done
		for k in vlan bridge interface ovs take_ownership; do
			v=$(os_get "network $net" "$k" "$r")
			[ -n "$v" ] && printf '  %s: %s\n' "$k" "$v"
		done
	done
	printf '\n'
}

os_plan_storage()
{
	local r storages s
	r=$1
	printf '## storage\n'
	storages=$(os_sections storage "$r" | sort)
	for s in $storages; do
		printf 'storage %s\n' "$s"
		printf '  type: %s\n' "$(os_get "storage $s" type "$r")"
		printf '  shared: %s\n' "$(os_get "storage $s" shared "$r")"
		printf '  existing: %s\n' "$(os_get "storage $s" existing "$r")"
		[ -n "$(os_get_all "storage $s" devices "$r")" ] && \
			printf '  devices: %s\n' "$(os_get_all "storage $s" devices "$r" | paste -sd, -)"
	done
	printf '\n'
}

os_plan_services()
{
	local r svcs want s st deps probe
	r=$1
	printf '## services (what would be installed, in dependency order)\n'
	# dependency order: identity first, then the rest
	svcs=$(os_sections service "$r" | sort)
	for want in keystone glance placement nova neutron-server horizon cinder; do
		for s in $svcs; do
			[ "$s" = "$want" ] || continue
			row=$(os_catalog_rows services | awk -F'|' -v n="$want" '$1 == n')
			probe=$(os_service_probe "$want" 2>/dev/null || true)
			st=${probe%% *}
			[ -n "$st" ] || st=pending
			printf 'service %s on %s [%s]\n' "$want" "$(os_get "service $s" node "$r")" "$st"
			deps=$(printf '%s\n' "$row" | awk -F'|' '{ print $3 }')
			[ -n "$deps" ] && printf '  depends: %s\n' "$(echo "$deps" | paste -sd, -)"
		done
	done
	printf '\n'
}

os_plan_operations()
{
	local r k
	r=$1
	printf '## operations\n'
	for k in init tls credentials db_node mq_node ha; do
		printf '  %-12s: %s\n' "$k" "$(os_get operations "$k" "$r")"
	done
	printf '\n'
}

os_plan_integration()
{
	local pending ready n reason
	# readiness is derived per service (installed or available in a
	# configured repository here), never from a maintained list: the
	# plan stays honest as native packages land
	pending=""; ready=""
	for n in $(os_catalog_rows services | awk -F'|' '{ print $1 }'); do
		reason=$(os_service_probe "$n" 2>/dev/null || true)
		case "$reason" in
		ready*) ready="$ready $n" ;;
		*) pending="$pending $n(${reason#pending })" ;;
		esac
	done
	printf '  pending services (not installable here):%s\n' "${pending:- none}"
	printf '  ready services (installed or in a repo):%s\n' "${ready:- none}"
	# hypervisor integration is derived with the same rule: the OVS
	# agents and nova-compute talk to libvirtd/QEMU, which this plan
	# does not install but records honestly
	if os_apk_ready qemu 2>/dev/null; then
		printf '  hypervisor (qemu/kvm, outside this plan): ready\n'
	else
		printf '  hypervisor (qemu/kvm, outside this plan): pending unavailable\n'
	fi
	printf '  ha: none until the HA stack is ported\n'
	printf '\n'
	printf 'This plan changes nothing. Applying it is a separate, explicitly\n'
	printf 'approved operation that does not exist yet.\n'
}

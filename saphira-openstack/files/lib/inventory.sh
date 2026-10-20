#!/bin/sh
#
# inventory.sh - the `inventory` interface: inspect and validate the
# operator's chosen configuration. Read-only: it never writes anything.
#
# Output is a human-readable rendering of the parsed and validated
# document, suitable for review before planning.

os_inventory_render()
{
	local file records domain init nodes n nets net fam cidr storages s svcs name row status k v extra
	file=$1
	os_reset_errors
	records=$(os_parse "$file") || { os_error "document does not parse"; return 1; }
	os_validate "$file" || return 1

	printf '# saphira-openstack inventory: %s\n' "$file"
	printf '# validated %s\n' "$(os_normalize "$file" | wc -l | tr -d ' ') lines of canonical content"
	printf '\n'

	domain=$(os_get global domain "$records")
	init=$(os_get global init "$records")
	printf 'global\n'
	printf '  domain = %s\n' "$domain"
	printf '  init   = %s\n' "$init"
	printf '\n'

	nodes=$(os_sections node "$records" | sort)
	printf 'nodes\n'
	for n in $nodes; do
		printf '  %-16s roles=%s address4=%s address6=%s\n' \
			"$n" \
			$(os_get_all "node $n" roles "$records" | paste -sd, -) \
			$(os_get "node $n" address4 "$records") \
			$(os_get "node $n" address6 "$records")
	done
	printf '\n'

	nets=$(os_sections network "$records" | sort)
	printf 'networks\n'
	for net in $nets; do
		printf '  %-16s purposes=%s family=%s existing=%s\n' \
			"$net" \
			$(os_get_all "network $net" purposes "$records" | paste -sd, -) \
			$(os_network_family "$records" "network $net") \
			$(os_get "network $net" existing "$records")
		for fam in 4 6; do
			cidr=$(os_get "network $net" "cidr$fam" "$records")
			[ -n "$cidr" ] || continue
			printf '    cidr%s=%s gw=%s mode=%s dns=%s\n' "$fam" "$cidr" \
				$(os_get "network $net" "gateway$fam" "$records") \
				$(os_get "network $net" "mode$fam" "$records") \
				$(os_get_all "network $net" "dns" "$records" | paste -sd, -)
		done
		extra=""
		for k in vlan bridge interface ovs take_ownership; do
			v=$(os_get "network $net" "$k" "$records")
			[ -n "$v" ] && extra="$extra $k=$v"
		done
		[ -n "$extra" ] && printf '    %s\n' "$extra"
	done
	printf '\n'

	storages=$(os_sections storage "$records" | sort)
	printf 'storage\n'
	for s in $storages; do
		printf '  %-16s type=%s shared=%s existing=%s\n' \
			"$s" \
			$(os_get "storage $s" type "$records") \
			$(os_get "storage $s" shared "$records") \
			$(os_get "storage $s" existing "$records")
		printf '    devices=%s\n' "$(os_get_all "storage $s" devices "$records" | paste -sd, -)"
	done
	printf '\n'

	svcs=$(os_sections service "$records" | sort)
	printf 'services\n'
	for s in $svcs; do
		name=$s
		status=$(os_service_probe "$name" 2>/dev/null | awk '{ print $1 }' || true)
		[ -n "$status" ] || status=pending
		printf '  %-16s node=%s status=%s\n' \
			"$name" \
			$(os_get "service $s" node "$records") \
			"$status"
	done
	printf '\n'

	printf 'operations\n'
	for k in init tls credentials db_node mq_node ha; do
		printf '  %-12s = %s\n' "$k" "$(os_get operations "$k" "$records")"
	done
}

os_network_family()
{
	local r sec fam
	# summarize which families a network carries
	r=$1; sec=$2
	fam=""
	[ -n "$(os_get "$sec" cidr4 "$r")" ] && fam="${fam:+$fam,}ipv4"
	[ -n "$(os_get "$sec" cidr6 "$r")" ] && fam="${fam:+$fam,}ipv6"
	[ -n "$fam" ] || fam=none
	printf '%s' "$fam"
}

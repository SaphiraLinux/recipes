#!/bin/sh
#
# detect.sh - read-only inspection of the local machine for wizard suggestions.
#
# The operator confirms every selection. These functions only ever READ:
# sysfs, link state, OVS configuration, ZFS pool status, routes, and the
# local init system. Nothing here modifies anything, and the wizard never
# treats a detected value as a chosen value.
#
# Suggestions are labelled as such; the operator must confirm each one.

os_detect()
{
	local kind
	kind=$1
	case "$kind" in
	interfaces | all) os_detect_interfaces ;;
	ovs | all) os_detect_ovs ;;
	vlans | all) os_detect_vlans ;;
	zfs | all) os_detect_zfs ;;
	routes | all) os_detect_routes ;;
	init | all) os_detect_init ;;
	esac
}

os_detect_interfaces()
{
	local d name type kind oper
	# Physical and virtual interfaces from sysfs, read-only. Loopback is
	# listed last and marked, never hidden: the operator decides.
	printf '# detected interfaces (read-only suggestion; confirm each)\n'
	for d in /sys/class/net/*; do
		[ -d "$d" ] || continue
		name=$(basename "$d")
		[ -f "$d/type" ] || continue
		type=$(cat "$d/type" 2>/dev/null || echo ?)
		case "$type" in
		1) kind=ether ;;
		*) kind=other ;;
		esac
		if [ -L "$d/device" ]; then
			kind="$kind pci"
		fi
		if [ -d "$d/wireless" ]; then
			kind="$kind wireless"
		fi
		oper=$(cat "$d/operstate" 2>/dev/null || echo unknown)
		printf '%s type=%s state=%s\n' "$name" "$kind" "$oper"
	done
}

os_detect_ovs()
{
	local b ports
	# Existing OVS bridges and their ports, via the ovs-vsctl read surface.
	# Read-only: listing configuration never changes it.
	printf '# detected OVS bridges (read-only suggestion; confirm each)\n'
	if command -v ovs-vsctl >/dev/null 2>&1; then
		for b in $(ovs-vsctl list-br 2>/dev/null); do
			ports=$(ovs-vsctl list-ports "$b" 2>/dev/null | tr '\n' ' ')
			printf '%s ports=%s\n' "$b" "$ports"
		done
	else
		printf '# ovs-vsctl not present: no Open vSwitch on this machine\n'
	fi
}

os_detect_vlans()
{
	local d name id parent f
	# VLAN interfaces and their parents, from sysfs, read-only.
	printf '# detected VLANs (read-only suggestion; confirm each)\n'
	for d in /sys/class/net/*; do
		[ -d "$d" ] || continue
		[ -f "$d/vlan_id" ] || continue
		name=$(basename "$d")
		id=$(cat "$d/vlan_id" 2>/dev/null || echo ?)
		parent=$(cat "$d/vlan_proc_name" 2>/dev/null || echo ?)
		printf '%s id=%s parent=%s\n' "$name" "$id" "$parent"
	done
	# kernel VLAN awareness on plain bridges
	if [ -d /proc/net/vlan ]; then
		for f in /proc/net/vlan/*; do
			[ -f "$f" ] || continue
			printf '# %s\n' "$(basename "$f")"
		done
	fi
}

os_detect_zfs()
{
	local line
	# ZFS pools and datasets, read-only. Listing never imports, mounts or
	# modifies anything.
	printf '# detected ZFS pools (read-only suggestion; confirm each)\n'
	if command -v zpool >/dev/null 2>&1; then
		zpool list -H -o name,,size,health 2>/dev/null | while read -r line; do
			printf 'pool %s\n' "$line"
		done
	else
		printf '# zpool not present: no ZFS userspace on this machine\n'
	fi
	printf '# detected ZFS datasets (read-only suggestion; confirm each)\n'
	if command -v zfs >/dev/null 2>&1; then
		zfs list -H -o name,type,used,available,mountpoint 2>/dev/null | \
			while read -r line; do
				printf 'dataset %s\n' "$line"
			done
	fi
}

os_detect_routes()
{
	# Kernel routing table, read-only.
	printf '# detected routes (read-only suggestion; confirm each)\n'
	ip route show 2>/dev/null
	ip -6 route show 2>/dev/null
}

os_detect_init()
{
	# The local init system, read-only, offered ONLY as a suggestion. The
	# operator still chooses; packages ship both init definitions and
	# neither is auto-enabled.
	printf '# detected init system (read-only suggestion; confirm)\n'
	if [ -L /sbin/init ] || [ -f /sbin/init ]; then
		printf 'init_path %s\n' "$(readlink -f /sbin/init 2>/dev/null || echo /sbin/init)"
	fi
	if [ -d /run/systemd/system ]; then
		printf 'init_detected systemd\n'
	elif [ -x /sbin/openrc ] || [ -d /etc/runlevels ]; then
		printf 'init_detected openrc\n'
	else
		printf 'init_detected unknown\n'
	fi
}

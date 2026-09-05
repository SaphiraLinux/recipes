#!/usr/bin/env bash

set -euo pipefail
umask 077

test "$(id -u)" -eq 0 || {
	printf 'apply-accounts: must be run as root\n' >&2
	exit 1
}

ROOTFS=${1:?derived rootfs path is required}
ACCOUNTS=${2:?accounts.tsv path is required}
ROOT=${SAPHIRA_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}

[[ $ROOTFS == "$ROOT/out/stage4/rootfs" ]] ||
	{ printf 'apply-accounts: unsafe rootfs: %s\n' "$ROOTFS" >&2; exit 1; }
test -d "$ROOTFS" || {
	printf 'apply-accounts: derived rootfs is absent\n' >&2
	exit 1
}
test ! -e "$ROOTFS/var/lib/saphira-firstboot/completed" || {
	printf 'apply-accounts: firstboot has already completed\n' >&2
	exit 1
}

declare -A gids=() users=() group_members=()
declare -A user_names=() group_names=() preserved_users=()
while IFS=$'\t' read -r name type id primary home shell supplementary; do
	case $name in
		''|'#'*) continue ;;
	esac
	case $type in
		group)
			test -z "${gids[$id]:-}" ||
				{ printf 'duplicate GID %s\n' "$id" >&2; exit 1; }
			gids[$id]=$name
			group_names[$name]=$id
			group_members[$name]=${supplementary//-}
			;;
		user)
			test -z "${users[$id]:-}" ||
				{ printf 'duplicate UID %s\n' "$id" >&2; exit 1; }
			users[$id]=$name
			user_names[$name]=$id
			;;
		*) printf 'invalid account type: %s\n' "$type" >&2; exit 1 ;;
	esac
done < "$ACCOUNTS"

passwd_new=$(mktemp "$ROOTFS/etc/passwd.stage4.XXXXXX")
group_new=$(mktemp "$ROOTFS/etc/group.stage4.XXXXXX")
shadow_new=$(mktemp "$ROOTFS/etc/shadow.stage4.XXXXXX")
cleanup_staging()
{
	rm -f -- "$passwd_new" "$group_new" "$shadow_new"
}
trap cleanup_staging EXIT
old_passwd=$ROOTFS/etc/passwd
old_group=$ROOTFS/etc/group
old_shadow=$ROOTFS/etc/shadow
firstboot_required=0
: > "$passwd_new"
: > "$group_new"
: > "$shadow_new"

while IFS=$'\t' read -r name type id primary home shell supplementary; do
	case $name in
		''|'#'*) continue ;;
	esac
	if test "$type" = user; then
		gid=
		for candidate in "${!gids[@]}"; do
			test "${gids[$candidate]}" != "$primary" || gid=$candidate
		done
		test -n "$gid" || {
			printf 'missing primary group for %s: %s\n' "$name" "$primary" >&2
			exit 1
		}
		gecos=$name
		test "$name" != root || gecos=root
		printf '%s:x:%s:%s:%s:%s:%s\n' \
			"$name" "$id" "$gid" "$gecos" "$home" "$shell" >> "$passwd_new"
		old_hash=$(
			awk -F: -v name="$name" '$1 == name { print $2; exit }' \
				"$ROOTFS/etc/shadow" 2>/dev/null || true
		)
		test -n "$old_hash" || old_hash='!'
		if test "$name" = root; then
			case $old_hash in
				'!'|'!*'|'*') old_hash=; firstboot_required=1 ;;
			esac
		fi
		if test "$name" = root && test "$firstboot_required" = 1; then
			printf '%s:%s:1:0:99999:7:::\n' "$name" "$old_hash" >> "$shadow_new"
		else
			printf '%s:%s:0:0:99999:7:::\n' "$name" "$old_hash" >> "$shadow_new"
		fi
	fi
done < "$ACCOUNTS"

# Preserve only human users that were deliberately created by the existing
# system-configuration flow. An unresolved numeric UID does not create a user.
while IFS=: read -r name password uid gid gecos home shell; do
	test "$uid" -ge 1000 && test "$uid" -lt 65534 || continue
	test -z "${users[$uid]:-}" && test -z "${user_names[$name]:-}" || {
		printf 'human account collision: %s UID %s\n' "$name" "$uid" >&2
		exit 1
	}
	printf '%s:%s:%s:%s:%s:%s:%s\n' \
		"$name" "$password" "$uid" "$gid" "$gecos" "$home" "$shell" \
		>> "$passwd_new"
	old_hash=$(awk -F: -v name="$name" '$1 == name { print $2; exit }' \
		"$old_shadow")
	test -n "$old_hash" || old_hash='!'
	printf '%s:%s:0:0:99999:7:::\n' "$name" "$old_hash" >> "$shadow_new"
	preserved_users[$name]=1
	if test -d "$ROOTFS$home"; then
		chown -R "$uid:$gid" "$ROOTFS$home"
	fi
done < "$old_passwd"

while IFS=$'\t' read -r name type id primary home shell supplementary; do
	case $name in
		''|'#'*) continue ;;
	esac
	test "$type" = group || continue
	members=${group_members[$name]:-}
	if test "$name" = wheel; then
		old_members=$(awk -F: '$1 == "wheel" { print $4; exit }' "$old_group")
		for member in ${old_members//,/ }; do
			test -n "${preserved_users[$member]:-}" || continue
			case ,$members, in
				*,"$member",*) ;;
				*) members=${members:+$members,}$member ;;
			esac
		done
	fi
	printf '%s:x:%s:%s\n' "$name" "$id" "$members" >> "$group_new"
done < "$ACCOUNTS"

while IFS=: read -r name password gid members; do
	test "$gid" -ge 1000 && test "$gid" -lt 65534 || continue
	test -z "${gids[$gid]:-}" && test -z "${group_names[$name]:-}" || {
		printf 'human group collision: %s GID %s\n' "$name" "$gid" >&2
		exit 1
	}
	printf '%s:%s:%s:%s\n' "$name" "$password" "$gid" "$members" \
		>> "$group_new"
done < "$old_group"

install -m 0644 "$passwd_new" "$ROOTFS/etc/passwd"
install -m 0644 "$group_new" "$ROOTFS/etc/group"
install -m 0600 "$shadow_new" "$ROOTFS/etc/shadow"
install -D -m 0755 "$ROOT/stage4/baselayout/saphira-firstboot" \
	"$ROOTFS/sbin/saphira-firstboot"
install -D -m 0644 "$ROOT/stage4/baselayout/root.profile" \
	"$ROOTFS/root/.profile"
chmod 0700 "$ROOTFS/root"
ln -sfn ../usr/bin/passwd "$ROOTFS/bin/passwd"
install -d -m 0700 "$ROOTFS/var/lib/saphira-firstboot"
install -D -m 0644 "$ROOT/stage4/config/network.d/00-loopback.conf" \
	"$ROOTFS/etc/network.d/00-loopback.conf"
if test "$firstboot_required" = 1; then
	install -m 0600 /dev/null "$ROOTFS/etc/saphira-firstboot-required"
else
	rm -f "$ROOTFS/etc/saphira-firstboot-required"
fi
cleanup_staging
trap - EXIT

install -d -m 0755 "$ROOTFS/var/empty" \
	"$ROOTFS/var/lib/bind" \
	"$ROOTFS/var/lib/nginx" \
	"$ROOTFS/var/lib/php-fpm" \
	"$ROOTFS/var/lib/dhcpcd" \
	"$ROOTFS/var/lib/haproxy" \
	"$ROOTFS/var/lib/mysql" \
	"$ROOTFS/var/lib/unbound" \
	"$ROOTFS/var/lib/dnsmasq" \
	"$ROOTFS/var/lib/kea" \
	"$ROOTFS/var/lib/chrony" \
	"$ROOTFS/var/spool/postfix" \
	"$ROOTFS/var/lib/dovecot" \
	"$ROOTFS/var/lib/valkey" \
	"$ROOTFS/var/lib/rspamd" \
	"$ROOTFS/var/lib/openvswitch" \
	"$ROOTFS/var/lib/clamav" \
	"$ROOTFS/var/lib/postgresql"
chown 0:11 "$ROOTFS/var/spool/mail"
chown 0:0 "$ROOTFS/var/empty"
if test -e "$ROOTFS/usr/bin/sudo"; then
	chown 0:0 "$ROOTFS/usr/bin/sudo"
	chmod 4755 "$ROOTFS/usr/bin/sudo"
fi
chown 102:102 "$ROOTFS/var/lib/nginx"
chown 103:103 "$ROOTFS/var/lib/php-fpm"
chmod 0700 "$ROOTFS/var/lib/postgresql"
chown 122:122 "$ROOTFS/var/lib/postgresql"

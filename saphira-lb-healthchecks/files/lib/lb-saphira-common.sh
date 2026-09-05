#!/bin/sh
# Saphira LB healthcheck common library.
# Copyright (c) 2026 AKADATA. MIT licensed.
#
# Caller ABI (ldirectord/HAProxy external checks) - NOTHING beyond these
# five is ever assumed from a caller:
#   $1 = virtual service / firewall mark
#   $2 = virtual port
#   $3 = real server address          (check target)
#   $4 = real server port
#   $5 = virtual source where supplied (optional)
#
# Everything else is check-specific CONFIGURATION, resolved in order:
#   1. explicit positional $6+          (manual use / adapter wrappers)
#   2. environment variable             (LB_SAPHIRA_*)
#   3. check/service config file        (see below)
#   4. safe default baked into the check
#
# Config layer: /etc/saphira/lb-healthchecks.d/
#   <check>.conf              settings for one check, all services
#   <check>/<service>.conf    per-service override (<service> = sanitized $1)
# Format: KEY=VALUE lines (KEY must match LB_SAPHIRA_[A-Z0-9_]+), lines
# starting with # are comments. Caller environment always wins over conf
# files; conf files win over baked-in defaults.
#
# Exit 0 healthy, non-zero unhealthy. Credentials arrive via environment
# or admin-owned conf files only and are never echoed. Every check
# enforces a bounded timeout.

lb_init()
{
	LB_VS="${1:-}"
	LB_VPORT="${2:-}"
	LB_REAL="${3:-}"
	LB_RPORT="${4:-}"
	LB_VSOURCE="${5:-}"
	LB_TIMEOUT="${LB_SAPHIRA_TIMEOUT:-3}"
	[ -n "$LB_REAL" ] || exit 2
	lb_conf_load
}

lb_conf_load()
{
	# Check name from the script name: lb.saphira.<check> -> <check>
	LB_CHECK=$(basename "$0" 2>/dev/null | sed -e 's/^lb\.saphira\.//')
	[ -n "$LB_CHECK" ] || return 0
	# Service token: sanitized $1 (FWM/VIP), path-component safe
	local svc
	svc=$(printf '%s' "$LB_VS" | tr -c 'A-Za-z0-9._-' '_' | sed -e 's/^_*//' -e 's/_*$//')
	local base="${LB_SAPHIRA_CONF_DIR:-/etc/saphira/lb-healthchecks.d}"
	local f key val
	for f in "$base/$LB_CHECK.conf" "$base/$LB_CHECK/$svc.conf"; do
		[ -f "$f" ] || continue
		while IFS= read -r line || [ -n "$line" ]; do
			case "$line" in ''|\#*) continue ;; esac
			key=${line%%=*}
			case "$key" in
				LB_SAPHIRA_[A-Z0-9_]*) ;;
				*) continue ;;
			esac
			val=${line#*=}
			val=${val%$'\r'}
			# strip one pair of surrounding quotes if present
			case "$val" in
				\"*\") val=${val#\"}; val=${val%\"} ;;
				\'*\') val=${val#\'}; val=${val%\'} ;;
			esac
			# caller environment always wins: only set unset variables
			eval "[ -n \"\${$key+x}\" ]" && continue
			export "$key=$val"
		done < "$f"
	done
}

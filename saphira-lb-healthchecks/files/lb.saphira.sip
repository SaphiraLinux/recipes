#!/bin/sh
# lb.saphira.sip - SIP OPTIONS round-trip over UDP or TCP (L7).
# Env: LB_SAPHIRA_SIP_PROTO (udp|tcp), LB_SAPHIRA_SIP_OK (max healthy
# status, default any 1xx/2xx), $5 vsource used in Via/From when present.
# Copyright (c) 2026 AKADATA LIMITED. BSL 1.1 licensed.
. /usr/share/saphira/lb-healthchecks/lib/lb-saphira-common.sh
lb_init "$@"
set -- sip --host "$LB_REAL" --port "${LB_RPORT:-5060}" --timeout "$LB_TIMEOUT" \
	--proto "${LB_SAPHIRA_SIP_PROTO:-udp}" \
	${LB_VSOURCE:+--vsource "$LB_VSOURCE"}
[ -n "${LB_SAPHIRA_SIP_OK:-}" ] && set -- "$@" --expect-status "$LB_SAPHIRA_SIP_OK"
lb_probe "$@"

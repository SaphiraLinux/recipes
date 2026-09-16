# saphira-lb-healthchecks

Generic external health-check library for Saphira load balancers
(ldirectord, HAProxy, and any caller with an executable/exit-status
interface). BSL 1.1 licensed. Clean-room implementation.

## Package rule: named check = named capability

A check must fail when its named capability fails. There are NO silent
fallbacks: `https` never degrades to `tcp`, `http3` never degrades to
`quic`, `dicom.echo` never degrades to "port open". A pass verdict
certifies exactly the promised transaction.

## Interface contract (ldirectord / HAProxy external checks)

**$1–$5 are the caller ABI. Nothing beyond these five is ever assumed
from a caller** — neither ldirectord nor LVS/HAProxy will pass more:

    $1  virtual service / firewall mark
    $2  virtual port
    $3  real server address            (the check target)
    $4  real server port
    $5  virtual source where supplied  (optional)

**Everything else is check-specific configuration**, resolved in order:

1. explicit positional `$6+` — manual use / adapter wrappers where the
   caller permits richer arguments (convenience only, never required)
2. environment variable (`LB_SAPHIRA_*`)
3. check/service config file (see below)
4. safe default baked into the check

That keeps the scripts pleasant to test manually, lets ldirectord pass
richer arguments where our adapter permits it, and never forces HAProxy
to support an interface it does not have.

### Configuration layer: /etc/saphira/lb-healthchecks.d/

    <check>.conf              settings for one check, all services
    <check>/<service>.conf    per-service override (<service> = sanitized $1)

Example — a DICOM modality that needs its own per-install settings
(`/etc/saphira/lb-healthchecks.d/dicom.find.conf`):

    LB_SAPHIRA_DICOM_PATIENT_ID=SAPHIRA-SYNTHETIC-HEALTHCHECK
    LB_SAPHIRA_DICOM_MODALITY=CT
    LB_SAPHIRA_DICOM_QUERY_LEVEL=PATIENT
    LB_SAPHIRA_DICOM_AET=SAPHIRA-HC
    LB_SAPHIRA_DICOM_AEC=MODALITY-SCP

Or per VIP/FWM in `dicom.find/<service>.conf`. Format: `KEY=VALUE`
lines, keys must match `LB_SAPHIRA_[A-Z0-9_]+`, `#` comments. Caller
environment always wins over conf files; conf files win over defaults.
The medical package (`saphira-lb-medical-healthchecks`) documents each
DICOM knob in its own README.

Exit 0 = healthy; non-zero = unhealthy; exit 2 = misconfiguration.
All checks enforce a bounded timeout (`LB_SAPHIRA_TIMEOUT`, default 3
seconds). All addresses are resolved via `getaddrinfo` (IPv4 and IPv6
where the protocol permits; raw-IP checks are IPv4 in v1). Credentials
arrive via environment or admin-owned conf files only and are never
echoed.

## Checks

| Check | Layer | Proves |
|---|---|---|
| lb.saphira.icmp | L3 | ICMP echo round-trip |
| lb.saphira.tcp | L4 | TCP accept |
| lb.saphira.udp | L4 | UDP listener bound (ICMP-unreachable discrimination) |
| lb.saphira.multiport | L4 | all/any of a port list accepts TCP |
| lb.saphira.http | L7 | HTTP status/body transaction |
| lb.saphira.https | L7 | HTTPS status/body transaction |
| lb.saphira.tls | L7 | full TLS handshake (+ optional cert-expiry floor) |
| lb.saphira.sni | L7 | TLS handshake asserting a specific SNI hostname |
| lb.saphira.dns | L7 | DNS query round-trip (ID/QR/rcode verified) |
| lb.saphira.smtp | L7 | SMTP greeting + EHLO + QUIT (stops before DATA) |
| lb.saphira.imap | L7 | IMAP greeting/CAPABILITY, no AUTH |
| lb.saphira.pop3 | L7 | POP3 greeting, no AUTH |
| lb.saphira.ldap | L7 | LDAP anonymous bind + rootDSE response |
| lb.saphira.ssh | L7 | SSH-2.0 banner handshake (credential-free) |
| lb.saphira.radius | L7 | RADIUS Status-Server (RFC 5997) round-trip |
| lb.saphira.sip | L7 | SIP OPTIONS round-trip (UDP or TCP) |
| lb.saphira.mysql | L7 | MySQL protocol handshake parse |
| lb.saphira.postgresql | L7 | PostgreSQL SSLRequest negotiation |
| lb.saphira.redis | L7 | Redis PING -> PONG (optional AUTH via env) |
| lb.saphira.quic | L7 | QUIC listener via Version Negotiation handshake |
| lb.saphira.http3 | L7 | STRICT real HTTP/3 transaction (no fallback) |
| lb.saphira.gre | L3 | GRE encapsulated-packet loopback (two-party contract) |
| lb.saphira.ipproto | L3 | raw IP protocol primitive (probe/accept modes) |
| lb.saphira.sendexpect.tcp | L4/L7 | raw TCP send-expect |
| lb.saphira.sendexpect.udp | L4/L7 | raw UDP send-expect |

Per-check environment knobs are documented in each script header.

## Probe engine

`/usr/bin/saphira-lb-probe` implements the raw/protocol probes behind a
stable CLI contract (see the module docstring). v1 is python3; a future
compiled binary must implement the same interface and replace this
payload. Protocol checks that map to standard tools (curl, openssl)
stay on those tools.

## GRE / ipproto notes

RFC 2784/2890 define the GRE header/key/sequence format only; the
keepalive loop used by `lb.saphira.gre` is the common tunnel-keepalive
practice, not a standard. It is a two-party contract:
`LB_SAPHIRA_GRE_INNER_SRC/DST/PORT` must be configured. `lb.saphira.ipproto`
in `accept` mode proves the protocol was NOT rejected by ICMP — evidence
of acceptance, not proof of health. Both require CAP_NET_RAW (root).

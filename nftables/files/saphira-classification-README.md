# Saphira nftables-native packet classification

## Purpose

A lightweight, Saphira-native packet classification layer built entirely
on nftables. It classifies traffic using kernel-native metadata and
publishes the results as packet marks, named sets and verdict maps that
enforcement chains (including `/etc/nftables.conf`) can consume. It is
deliberately NOT an IDS/IPS: no Suricata-style application stack, no
SaaS, no cloud lookups, no telemetry leaving the box.

## Architecture

```
                ┌────────────────────────────────────────────┐
                │  saphira_classify (priority -150)          │
                │  ct / interfaces / osf / rate → marks+sets │
                └───────────────┬────────────────────────────┘
                                │ marks, sets, maps
                ┌───────────────▼────────────────────────────┐
                │  enforcement (inet filter / nat, etc.)     │
                │  consumes marks and sets; owns the policy  │
                └───────────────┬────────────────────────────┘
                                │ (optional, operator-enabled)
                ┌───────────────▼────────────────────────────┐
                │  NFQUEUE extension point (queue num 100)   │
                │  reserved for DNSDragon / small verifiers  │
                └────────────────────────────────────────────┘
```

* Classification runs at priority -150 (before the default
  `filter`/`nat` hooks) so every later chain can act on the marks.
* Enforcement stays in nftables. The classifier never drops traffic by
  itself except for explicitly operator-configured offender rules.
* Results are reusable: `meta mark`, named sets (`offenders4`,
  `infrastructure4`) and the `osf_policy` verdict map.

## What can be classified reliably

| Metadata                        | Notes                                            |
|---------------------------------|--------------------------------------------------|
| L3/L4 protocol, ports           | always                                           |
| interfaces (iif/oif)            | always                                           |
| addresses, sets, intervals      | always                                           |
| ct state, direction, lifetime   | connection-scoped attributes                     |
| OS fingerprint (`osf`)          | SYN fingerprint at connection setup (passive)    |
| rate / burst behaviour          | per-source/destination, dynamic sets             |
| packet/byte counters            | baselining and alerting                          |

## What cannot be classified

Anything inside encrypted payloads (TLS, QUIC, VPN). DNS names are
classified only through the planned DNSDragon resolver integration, and
only for resolvable flows - never by payload sniffing. OS fingerprints
describe the *host's* stack, not the user's application.

## Kernel requirements

Enabled in saphira-kernel r3 (7.1.5-r3 / 7.2.2-r3, 2026-09-01):

* `CONFIG_NFT_OSF=m`, `CONFIG_NETFILTER_NETLINK_OSF=m` (passive OSF)
* `CONFIG_NFT_QUEUE=m`, `CONFIG_NETFILTER_NETLINK_QUEUE=m` (NFQUEUE)
* `CONFIG_NFT_FIB_NETDEV=m` (FIB matching on the netdev family)
* `CONFIG_BATMAN_ADV=m` (mesh; BATMAN V negotiation)
* full NAT/reject/connlimit/TPROXY/socket/fib stack was already =y
* upstream note: `NFT_RT` has no Kconfig entry in 7.2.2 (dead source);
  route matching uses `nft fib` instead.

## Usage

Review, then load:

    nft -f /usr/share/nftables/saphira/saphira-classification.nft

Check what got classified:

    nft list table inet saphira_classify

The NFQUEUE hook is intentionally empty: no queue rules are installed
until a userspace classifier ships. Nothing is sent to userspace by
default.

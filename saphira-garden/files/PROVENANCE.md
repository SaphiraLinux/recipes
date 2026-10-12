# PROVENANCE

Saphira Garden is an independent implementation of a TUN-based network access
controller with a walled garden, RADIUS integration and a captive portal.

It is **not** derived from the source code of ChilliSpot, CoovaChilli, or any
derivative of those works.

## Why the clean-room method is mandatory, not merely preferred

ChilliSpot 1.1.0 and CoovaChilli are licensed under the **GNU General Public
License version 2** (ChilliSpot's `COPYING` is GPLv2; the CoovaChilli fork's
`LICENSE` is "GPL version 2 or, at your option, any later version"). GPLv2
grants rights to redistribute and to modify, but it does **not** grant the
right to relicense. GPLv2 source cannot be placed under the Business Source
License 1.1, which is the licence Saphira Garden ships under.

Consequently: any copied source would taint the product and make it
unsellable. The clean-room discipline is a hard legal requirement. It also
happens to be the discipline that produces the better architecture, so there is
no tension between the two.

Note also that the reference fork carries a live compliance gap of its own:
approximately thirty files were modified without the GPLv2 section 2(b) notice
stating that the files were changed, while `CREDITS` still asserted that the
version "is being maintained by Coova". Saphira Garden avoids that problem
rather than inheriting it.

## Source classes

Every behavioural fact implemented in Saphira Garden is recorded in the ledger
below with one of these source classes.

| Class | Admissible |
|---|---|
| **S1** — Protocol specification (an RFC, or a published standard) | yes |
| **S2** — Published schema or registry (IANA RADIUS attribute registry, WISPr XML, FreeRADIUS dictionary) | yes |
| **S3** — Black-box observation of a reference implementation on the wire (packet capture) | yes |
| **S4** — Test assertion present in this repository | yes, and preferred |
| **S5** — Source code of the reference implementation | **no** |

Class S5 is listed here so the rule is explicit and auditable. Any fact that
could only be learned by reading the old implementation is re-derived from a
capture (S3) or written as a test (S4) instead.

## Ledger

| Area | Fact | Source |
|---|---|---|
| DHCP | Option 53 message types, 51 lease time, 1/3/15/119/15 codes, DISCOVER/OFFER/REQUEST/ACK/NAK/RELEASE/INFORM | S1 RFC 2131, RFC 2132 |
| DHCP | Broadcast before OFFER, unicast to ciaddr after REQUEST | S1 RFC 2131 §4.1 |
| DHCP | giaddr non-zero means relay; reply destination rules | S1 RFC 2131 §4.1 |
| RADIUS | Code, length, identifier, Request/Response Authenticator layout and computation | S1 RFC 2865 §3 |
| RADIUS | User-Password encryption scheme | S1 RFC 2865 §5.2 |
| RADIUS | Message-Authenticator is HMAC-MD5 over the packet with the field zeroed | S1 RFC 3579 |
| RADIUS | Accounting Request/Response authenticator, Acct-Status-Type values | S1 RFC 2866 |
| RADIUS | CoA/Disconnect codes, NAS-Port-Type | S1 RFC 5176, RFC 2865 |
| RADIUS | EAP-Message (79) is an opaque octet string to the NAS | S1 RFC 3579 |
| RADIUS | Attribute numbers | S2 IANA registry |
| RADIUS | FreeRADIUS 3 server behaviour, module semantics, dictionary load | S2 FreeRADIUS documentation, observed in `/etc/raddb` on the test host |
| RADIUS | NAS-Port-Type 19 = Wireless-IEEE-802.11 | S1 RFC 2865 §5.15 |
| IPv6 RA | Message layout, ICMPv6 type 134, code 0, hop limit 255, Router Lifetime, Prefix Information option, Recursive DNS Server option | S1 RFC 4861 §6.2, RFC 4862 §4 |
| IPv6 RA | M flag semantics: set only if the sender offers DHCPv6 | S1 RFC 4861 §6.2.4 |
| IPv6 RA | Source address must be a link-local address | S1 RFC 4861 §6.1.2 |
| IPv6 ND | NS/NA, types 135/136, DAD from the unspecified address with a null SLLA | S1 RFC 4861 §7.1, §7.2, §7.1.4 |
| IPv6 | Link-local address synthesis from a link-layer address, with the U/L bit inverted | S1 RFC 4291 §2.5.1 |
| IPv6 | SLAAC, temporary (privacy) addresses, and that a device may hold several addresses | S1 RFC 4862 §5.5, RFC 8981 |
| IPv6 | NDP options 1 (SLLA), 2 (TLLA) | S1 RFC 4861 §4.4 |
| IPv6 | No NAT for IPv6; routing rather than translation | S1 RFC 4864, RFC 8981 preamble |
| DHCPv6 | IA_NA, IA_PD, message and option structure, Rapid Commit | S1 RFC 8415 |
| DHCPv6 | IA_NA is a DHCPv6 construct; ND means Neighbour Discovery. The two are unrelated. | S1 RFC 8415, RFC 4861 |
| ARP | Request/reply layout, gratuitous ARP, gratuitous NUD | S1 RFC 826, RFC 5227 |
| Portal | WISPr XML document and element structure, ResponseCode values, Redirection URL, Logoff URL | S2 WISPr XML schema and ACME WISPr documentation |
| Portal | WISPr-BillTo-Usage is absent from our WISPr material and is not implemented | S2 — verified absent in the reference documentation set |
| Captive portal | CAPPORT API URI advertisement in DHCP option 114 with its placeholder grammar | S1 RFC 8910 |
| Captive portal | `application/captive+json` and the `/captive-portal-identification` resource | S1 RFC 8908 |
| MAC filtering | MAC-based RADIUS authentication using Calling-Station-ID and a derived password | S1 RFC 2865/3579 attribute usage |
| Accounting | Interim-Update driven by Acct-Interim-Interval; Start on authorisation; Stop on teardown | S1 RFC 2866 |
| Transport | CoA/Disconnect request validation using the same authenticator check as accounting | S1 RFC 5176 |

### Facts deliberately **not** taken from the reference

| Reference behaviour | Why not adopted |
|---|---|
| RA with the M (Managed) flag set while providing no DHCPv6 addressing | Contradicts RFC 4861 semantics; makes clients start DHCPv6 for nothing |
| RA carrying a 1500-byte MTL by default on a link that carries no such MTU | Advertises an MTU the link cannot use |
| PIO prefix length hard-coded to 64 with fixed lifetimes | Not a decision the daemon should be making implicitly |
| Answering a Router Advertisement in response to an MLDv2 report | Undefined behaviour |
| DHCPv6 message types 36/37 as "address registration", described as RFC 9686 | Not RFC 9686. RFC 9686 is ICMPv6 types 144/145 with ND options 33/34 |
| AAAA queries rewritten to A, and A answers rewritten to AAAA | Hands the client a false answer |
| Suppressing replies to foreign DAD probes | Behaviour is correct; it is reimplemented with a stated reason rather than inherited as a workaround |
| `MD5(query || secret)` as portal request integrity | A keyed checksum, not a MAC. Replaced with HMAC; legacy retained only as clearly-labelled compat |
| Verifying a RADIUS reply by source address and port only | Does not authenticate the reply. See below |
| Requesting the next-hop MAC via `SIOCGIFHWADDR` on a bridge | Not needed; the access socket already sees the frame |
| Renewing leases in the background | Deferred |

## Deliberate differences from the reference

Each of these is a decision, and each is tested.

| Reference | Saphira Garden | Why |
|---|---|---|
| RADIUS replies authenticated only by source address/port and queue id | Response Authenticator verified on every reply; Message-Authenticator verified when present; failure changes no state | A host reaching UDP 1812 could otherwise inject an Access-Accept |
| TUN creation failure ignored; daemon runs with an invalid descriptor | Fatal at startup, exit non-zero | A NAC device that appears healthy while enforcing nothing is worse than one that is visibly down |
| IPv6 walled-garden match reads 16 bytes from a 4-byte field and matches exact addresses only | Real longest-prefix match, shared structure for both families | The reference's IPv6 garden never matches a CIDR, and performs an out-of-bounds read doing it |
| Walled garden is a linear scan of a flat list per packet | Longest-prefix structure with bounded lookup | Scale, and correctness |
| DNS-derived garden entries have no expiry | Explicit expiry derived from the answer's TTL | An entry should not outlive its justification |
| Session on restart: everything destroyed | Measured first, then designed; restored state is revalidated with RADIUS | Old behaviour was an accident, not a design |
| Portal challenge regenerated per request in a forked process | Generated once per session, served in-process | The reference's model races on the challenge |
| Portal integrity via a keyed MD5 checksum | HMAC-SHA256, constant-time compare | The old construction is not a MAC |
| SUID-root `chilli_script` helper | No setuid helper at all; privilege is dropped permanently | A privilege boundary that is not needed should not exist |
| Config is a flat `key value` file with everything a string | Typed TOML, validated, `-t` mode, no unknown keys, no silent coercion | Twenty years of config baggage is not inherited |
| ~30 configure personalities, one of which cannot compile | No configure system. Plain `make` | A build system that generates 7,000 lines of C is a liability |
| `in6_addr` DNS rewrite to fake v4 | No such rewrite | It lies to clients |
| Tenant-wide OpenSSL legacy provider load for MSCHAPv2 | No legacy provider, because no MSCHAPv2 and no MD4/DES | FreeRADIUS performs MSCHAPv2. Loading `legacy` also silently breaks default-provider fetches process-wide if done carelessly |

## Etymology and lineage

The design lineage is ChilliSpot -> CoovaChilli. That lineage is recorded here
and in `docs/01-capability-matrix.md`, which audits it. It is deliberately
**not** carried in the product name: this is `saphira-garden`, because it is a
walled-garden NAC system and not a continuation of that codebase.

## Verification of this claim

Because Saphira Garden is distributed as a binary and as source, and because it
ships under a source-available licence, a reviewer can check the claim directly:

1. Saphira Garden is **not** an adaptation of the reference source; it is an
   implementation against the specifications named in the ledger.
2. No file, and no substantial portion of any file, has been copied from
   ChilliSpot or CoovaChilli.
3. Where behaviour coincides with the reference, it coincides because both
   implement the same published specification.
4. Every behavioural commitment in this repository is backed by a test in
   `tests/`, so conformance is checkable independently of provenance.

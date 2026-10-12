# saphira-udpdist — capability / claim matrix

Subject: the `saphira-udpdist-0.1.0-r1` source tree at keeper
`03f6658`, built and exercised on Egg.

A behaviour is listed as a claim only where `README.md`, `man/udpdist.1`, a
shipped example configuration, or the code states it. "Doc" cites the source.

## Legend for the verdict column

`M` measured in the lab · `C` code-confirmed only · `T` covered by a shipped
rootless test · `-` no test anywhere

---

## 1. The distributed property

| ID | Claim | Doc | Implemented at | Shipped test | Verdict |
|----|-------|-----|----------------|--------------|---------|
| C1 | Accepts UDP on one or more frontend address/port pairs and redirects each flow at layer 2 to a selected backend | README, man | `udpdist.c:process_frame`,`send_frame` | `tests/regress.sh` (parse/select), `lab.sh` | M |
| C2 | No address is rewritten: the backend observes the real client and replies directly | README "distributor, not a proxy" | `send_frame` (frame bytes reused, MAC rewritten only) | `lab.sh` "every reply came from the VIP itself" | M |
| C3 | The distributor is not on the return path | README | `send_frame` | `lab.sh` reply source == VIP | M |
| C4 | Ordinary UDP needs no state table and no per-flow descriptor | README | `hrw_select` is a pure function; no flow table exists | `lab.sh` (200 flows, one process, 3 fds) | M |
| C5 | IPv4 and IPv6 are both first class | README, man | `frame.c:parse_v4`,`parse_v6` | `unit.c` IPv6 ext-header walk, `lab.sh` | M |
| C6 | The selection score depends on backend identity and the flow, never on array position | README, man | `hrw.c:hrw_select` | `unit.c` 200/200 across three orderings; `lab.sh` reorder | M |
| C7 | Removing a backend moves only its own flows; survivors do not move | README, man | `hrw.c` skips unhealthy | `unit.c` survivor check; `lab.sh` | M |
| C8 | One client's consecutive source ports still spread across the pool | (derived from C6) | `hrw.c` | `unit.c` 74/61/65 over 200 ports | M |

## 2. QUIC and HTTP/3

| ID | Claim | Doc | Implemented at | Shipped test | Verdict |
|----|-------|-----|----------------|--------------|---------|
| C10 | QUIC and HTTP/3 traverse without terminating TLS and without parsing HTTP | README, man | `quic.c` reads only the connection id | `http3-lab.sh` real exchange | M |
| C11 | A short-header connection id has no length field, so the length comes from the QUIC-LB configuration codepoint, never from a guess | README, man | `quic.c:quic_classify` | `unit.c`; `http3-lab.sh` | M |
| C12 | Both standard length mechanisms work: per-configuration `cid_len` and self-description | README, man | `quic.c` | `unit.c` (self-describing and fixed) | M |
| C13 | `quic_mode=fallback` needs nothing from the backends and makes no migration claim | README, man | `quic.c` bounded 4-tuple table | `unit.c` stickiness | M |
| C14 | `quic_mode=quic_lb` routes established traffic from the connection id, and is the mode that earns the migration-safe claim | README, man | `quic.c` | `http3-lab.sh` rebind + migration | M |
| C15 | Affinity survives a source-port change on a live connection | README, man | `quic.c` CID routing | `http3-lab.sh` "rebind ... same backend=True" | M |
| C16 | Affinity survives a source-address change, including across address families | README, man | `quic.c` CID routing | `http3-lab.sh` "[::]:49000 -> 198.51.100.101:49001" | M |
| C17 | A codepoint match with an unknown server id falls back rather than dropping | README, man | `quic.c` | `unit.c`; measured, see RESULTS.md F-3 | M |
| C18 | An established connection whose backend failed is dropped and counted, never re-routed | README, man | `quic.c` | `unit.c` "never silently remapped" | M |
| C19 | `quic_lb` with absent or invalid id configuration fails validation | man | `config.c` | `regress.sh` | T |
| C20 | A frontend is never reported as QUIC-LB merely because it carries QUIC | README | `dump_stats` per-frontend `quic_mode` | read from lab output | M |
| C21 | Encrypted connection ids are not implemented and are not supported | README, man | absent by design | - | C |
| C22 | Six simultaneous QUIC connections are all established and served | (lab requirement) | - | `http3-lab.sh` 6/6 | M |
| C23 | Reordering the configuration moves no QUIC flow | README (inherited) | `hrw_select` | `http3-lab.sh` — **see RESULTS.md F-5** | not proven |

## 3. Operations

| ID | Claim | Doc | Implemented at | Shipped test | Verdict |
|----|-------|-----|----------------|--------------|---------|
| C30 | Health probing never blocks the event loop | README | `health.c` in-process ICMP, no fork | `regress.sh` no `exec` | M |
| C31 | The daemon establishes that probing works before accepting traffic | man | `health_selftest` | `lab.sh` start | M |
| C32 | A bad or missing backend hardware address is fatal at startup | README, man | `validate_backends` | `regress.sh`, `lab.sh` | M |
| C33 | A reload cannot silently stop forwarding | man | `carry_fds` ownership transfer | `lab.sh` reload + reorder | M |
| C34 | A reload needing a new layer 2 socket or a privileged bind is refused whole | man | `carry_fds` | - | C |
| C35 | The daemon creates its sockets, drops to `udpdist`, retains no capability, and proves the drop | README, man | `udpdist.c:drop_privileges` | `lab.sh` uid 127 | M |
| C36 | `--check` validates a configuration without privilege or sockets | man | `main` | `regress.sh` | T |
| C37 | Multicast and broadcast are rejected and counted, not silently accepted | README | `frame.c` | `unit.c` | T |
| C38 | The package is dependency-free C11 with no libraries | README | `src/Makefile` | build, `ldd` shows libc only | M |
| C39 | Checksum offload must be off on every redirected interface, and is enforced at startup | README, man | `csum_offload_is_on` | `lab.sh` sets it | M |
| C40 | No shell and no nftables path exists in the daemon | README | none | `regress.sh` greps for both | T |

## 4. Bounds

| Bound | Value | Enforced where | Documented |
|-------|-------|----------------|-----------|
| Frontends per service | 32 | `config.c` | man |
| Backends per service | 64 | `config.c` | man |
| Interfaces per service | 8 | `config.c` | man |
| Fragment associations | 4096, short lived | `frag.c`, `fragment_table_full` | man |
| QUIC fallback affinities | 4096, short lived | `quic.c` | man |
| Accepted datagram | `max_datagram`, 64..65535 | `config.c`, `frame.c` | man |
| Service name charset | `[A-Za-z0-9_-]` | `name_is_valid` | man |
| Config line length | 1023, longer refused | `config.c` | man |

## 5. Known operational constraint, not yet in the man page

Two services on one host must not share backends. Each opens its own ICMP
probe socket, the kernel delivers an echo reply to one matching socket only, and
so the services mark each other's backends down. Measured in RESULTS.md F-4.

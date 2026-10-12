# saphira-gredist capability / claim matrix

Subject of the acceptance run: the **published** `saphira-gredist-0.1.0-r5` from
the live `hatched` repository, installed on nodea / nodeb / nodec.
Binary under test (identical SHA-256 on all three hosts):

```
d0da71b952273992d981b836c3f78f2c82f1bb98b4a7984ae919fe82de310d66  /usr/bin/gredist
d38d904fdfba91f22d3af4ded83b4724cc74887facda88324ec41f44ae1a0d99  /usr/bin/gre-sink
577980995115e20c1eedf31953a3809fb586d49a5051d02de795ede22d52ddc6  /usr/bin/gre-send
```

Nothing in this file is inferred from the project name. A behaviour is listed as a
claim only where README.md, man/gredist.1, the shipped example config, or the code
actually states it. "Doc" cites the source of the claim.

## Legend for the verdict column

`M` measured on three real hosts · `C` code-confirmed only (not exercised) ·
`T` currently covered by a shipped test · `-` no test anywhere

---

## 1. Claims that describe the actual distributed property

| ID | Claim | Doc source | Implemented at | Shipped test | Verdict basis |
|----|-------|-----------|----------------|--------------|---------------|
| C1  | Distributes raw Protocol 47/GRE from a single frontend address to a pool of backends | README:3,6 | `src/gredist.c` main loop 353-485; `forward_packet` 174-221 | lab.sh prints only, `do_run` always exits 0 | M |
| C2  | One host may run multiple independent named services; each has exactly one frontend and one or more backends | README:9 | `main()` 245-278 loads **one** service per process; `config.c` 47-50 rejects a second `frontend=`; `config.c` 119-122 rejects zero backends | - | M |
| C3  | Config is `/etc/saphira/gredist/<service>.conf` with `frontend=IP` and repeatable `backend=IP` | README:13-19, man:16-24 | `config.c:21-124`; name resolution + charset check `gredist.c:259-275` | run-tests.sh "config parse" is vacuous (`--help` short-circuits before config load) | M |
| C4  | IPv6 uses the same config syntax | README:21-26, man:24 | `config.c:66-72` | run-tests.sh ipv6 outer parse only | M |
| C5  | Mixed pools supported (v4 frontend to v6 backends and vice versa); when families differ the outer IP envelope is terminated and rebuilt while GRE header and inner payload are preserved unchanged | README:28, man:24 | `parse_outer` `gre.c:33-100`; `forward_packet` `gredist.c:174-221` sends `gre_start..pkt_len` on a family-matched raw socket so the kernel rebuilds the outer header | lab.sh `test_v4_to_v6` / `test_v6_to_v4` / `test_mixed` assert nothing | M |
| C15 | Receive on a raw `IPPROTO_GRE` socket bound to the frontend, strip outer IP, select a backend, send `GRE+inner` to it; kernel builds the new outer header; same-family preserves payload, cross-family rebuilds it | README:52 | `gredist.c:297-336` (recv), 174-221 (send) | - | M |

**C1/C15 are the only genuine cross-host properties gredist has.** There is no
inter-node control plane, no cluster membership, no consensus, no replication and
no shared state of any kind between hosts. The word "distributed" in this project
means only "the forwarding decision is taken on one host and the packet is
delivered to another". Backend health is a one-directional ICMP probe; backends
are never told they are in a pool. Anything stronger is not implemented.

## 2. Protocol / parsing claims

| ID | Claim | Doc source | Implemented at | Shipped test | Verdict basis |
|----|-------|-----------|----------------|--------------|---------------|
| C10 | GRE parsing follows `net/ipv4/gre_demux.c:gre_parse_header`: validate the 4-byte base, reject `GRE_VERSION` and `GRE_ROUTING`, compute `gre_calc_hlen` from `CSUM\|KEY\|SEQ`, fail closed on truncated claims, support keyless and keyed | README:46, man:37 | `gre_parse` `gre.c:106-153` | run-tests.sh covers truncated + version; routing and CSUM untested | C/M |
| C11 | Malformed input (version, routing, truncated option, fragment, oversized >9000) is dropped and counted | README:46, man:37 | `gredist.c:414-470`; frag detected in `parse_outer` `gre.c:52-58` | lab.sh malformed/frag/oversized `echo PASS/FAIL` without affecting exit status | M |
| C20 | The GRE key is a visible identifier, not a secret | README:46, man:37 | no key validation anywhere | - | C |
| C16 | RCVBUF 4 MiB, `ENOBUFS` counts as a queue drop, fragments detected via `frag_off`, loss simulated with harness netem | README:54 | `gredist.c:311-312` sets 4 MiB **and never checks the return**; `gredist.c:211-218` maps every `sendto` failure to `dropped_queue`; `lab.sh:437-455` netem on the frontend veth | queue/loss tests assert nothing | M |

## 3. Distribution / health claims

| ID | Claim | Doc source | Implemented at | Shipped test | Verdict basis |
|----|-------|-----------|----------------|--------------|---------------|
| C12 | Rendezvous/HRW on `outer_src \|\| gre_key`; score = `splitmix64(fnv1a(backend_str) XOR flow_hash)`; pick the max among healthy backends | README:48, man:39 | `select_backend` `gre.c:155-192`; `backend_compute_hash` `gre.c:27-30` | run-tests.sh asserts same-flow determinism only | M |
| C13 | Removal of a backend moves only its flows; surviving mappings remain stable; rejoin is deterministic | README:48, man:39 | `gre.c:180` skips unhealthy so surviving scores are untouched; but `gre.c:182` mixes the **array index** `i` into the score | run-tests.sh only covers the health-removal path | M |
| C14 | Active ICMP `ping -c1 -W1` per backend every 2 s, 2 fails to down, 2 successes to up, transitions logged, and forwarding to no healthy backend drops | README:50, man:41 | `probe_backend` `gredist.c:80-106` (fork + exec, **synchronous**); `health_check` `gredist.c:108-131`; no-healthy drop `gre.c:189-191` -> `gredist.c:473-476` | lab.sh sleeps and prints; never asserts a transition time | M |
| C22 | No healthy backend means the packet is dropped | man:41 | `gre.c:190` returns -1 -> `dropped_no_backend` | - | M |

## 4. Operations claims

| ID | Claim | Doc source | Implemented at | Shipped test | Verdict basis |
|----|-------|-----------|----------------|--------------|---------------|
| C6  | `gredist <service>`, `gredist -c <path>`, `gredist --syslog <service>` | README:32-36, man:5-10 | `gredist.c:245-275` | - | M |
| C7  | Requires `CAP_NET_RAW`, usually `CAP_NET_ADMIN`; logs to stderr by default, syslog with `--syslog` | README:38 | sockets `gredist.c:300,314,328,330`; `openlog` 280. No privilege drop, no capability check, no non-root mode | - | M |
| C8  | `SIGHUP` reloads config, `SIGUSR1` dumps stats, `SIGTERM`/`SIGINT` exit | README:40, man:43-48 | `sig_handler` 67-71; reload 354-373; dump 223-236,374; exit 353,487-494 | - | M |
| C9  | Kernel handles an optional `nft` fast path (same-family DNAT via `inet` table `saphira_gredist_<name>`); userspace still owns HRW | README:44 | `try_setup_nft` `gredist.c:134-168` creates the table and **an empty** `nat prerouting` chain, then logs `"(placeholder, userspace owns HRW)"`. No DNAT rule is ever added | - | M |
| C19 | `/run/saphira/gredist/` is a documented file path | man:52 | `DEFAULT_STATS_PATH` `gredist.c:46` is **never used**; no directory is ever created; stats exist only in the log | - | M |
| C21 | Per-service and per-backend counters are observable | implied by C8 `SIGUSR1` | `dump_stats` `gredist.c:223-236`; counters are in-memory only | - | M |
| C23 | Exactly one frontend, at least one backend; comments start with `#` or `;`; families are not tied | man:35 | `config.c:36,47-50,115-122` | run-tests.sh "mixed family config" | M |

## 5. Build / packaging claims

| ID | Claim | Doc source | Implemented at | Shipped test | Verdict basis |
|----|-------|-----------|----------------|--------------|---------------|
| C17 | `make -C files/src` builds with `-march=x86-64-v3`; `ARCH=native` or `ARCH=` selects otherwise; C11 and Linux headers only; musl compatible | README:56-69 | `files/src/Makefile:1-11`; `recipe.sh:34-39` (fails closed on unknown `SAPHIRA_ARCH`) | build is exercised by the queue | M |
| C18 | BUSL-1.1 | README:96, man:56 | `LICENSE`, `recipe.sh` | - | M |
| -  | gredist provides a runnable **service** | implied by "control service" in man:13 | **no init script, no systemd unit, no sysusers fragment, no account is shipped** | - | M |

---

## INV-1 — observed-disposition invariant (added by this audit)

> Every packet the daemon accepts must have an observed disposition: delivered
> exactly once where delivery is promised, **or** accounted for by a named drop
> counter. Silent disappearance is a failure.

Accounted for every run as:

```
sent  ==  forwarded + (malformed + truncated + oversized + frag + version
                       + no_backend + queue)
Σ sink packets received == forwarded
```

This is what turns the suite from a pile of packet tests into an accounting
check, and it is the only test that can catch a packet vanishing without a
counter being touched. Known candidates it is designed to expose, from code
reading, each to be confirmed by measurement in P4/P5:

- `gredist.c:456-458` — `if(!dst_match){ continue; }` increments **no counter**.
  A packet whose outer destination is not the frontend disappears silently.
- `gredist.c:415-417` — oversized increments `dropped_oversized` **and**
  `dropped_malformed`, so one packet is counted twice and `sent == forwarded +
  Σdrops` is violated by exactly the oversized count.
- `dropped_oversized` is never printed by `dump_stats` (223-236), so it is not
  observable even though C11 claims oversized is "counted".
- `gre.c:60` / `gre.c:99` — a non-47 protocol or a failed IPv6 `parse_outer`
  returns -1 and is counted as malformed, which conflates several distinct
  reasons. `parse_outer` never returns -2 for IPv6, so **IPv6 fragments are
  counted as malformed, not as fragments**, contradicting C11 for the v6 path.
- `gredist.c:423-441` — on `recv6`, any `parse_outer` failure takes the
  headerless fallback *before* the `prs==-2` fragment branch, forces
  `dst_match=1`, and re-parses the IPv6 header as a GRE header.

---

## Undocumented assumptions (not stated anywhere in the docs)

1. **Open relay.** Nothing validates the sender. Any host that can reach the
   frontend gets its protocol-47 traffic forwarded into the backend pool. There
   is no source allowlist, no per-key ACL, no rate limit and no authentication.
   The key is explicitly not a secret (C20), so the pool is reachable by anyone
   with L3 reachability.
2. **Source address is route-selected, not frontend-derived.** The daemon sends
   to a backend sockaddr and lets the kernel pick the outer source, so on a
   multi-homed host the GRE outer source is whatever egress path routing selects.
3. **Health is optimistically up.** `config.c:106` sets `healthy=1` at load, so a
   dead backend receives traffic for the first ~4 s, and a `SIGHUP` reload
   re-marks every backend healthy, including ones previously proven down.
4. **Synchronous health probing shares the dataplane thread.** `health_check` is
   called inline from the event loop and blocks up to 2 s per unresponsive
   backend, per 2 s tick.
5. **IPv6 link-local needs a scope.** `inet_pton` is the only parser, so `fe80::1`
   and any `%iface` form cannot be expressed in a config.
6. **No buffering, no backpressure.** The send socket is non-blocking
   (`gredist.c:336`); `EAGAIN` is counted and the packet is discarded. There is no
   queue, no retry, no reordering — the dataplane is strictly best-effort and
   sequential per packet.
7. **RCVBUF is requested, not guaranteed.** `setsockopt` return values are
   discarded; `net.core.rmem_max` is exactly 4 MiB on these hosts so the claim
   holds here by coincidence, and is silently clamped anywhere it is lower.
8. **Reload re-reads the file but not the socket.** See C8/F-4 below.

## Bounds

| Bound | Value | Enforced where | Documented? |
|-------|-------|----------------|-------------|
| Backends per service | 64 (`MAX_BACKENDS`) | `config.c:79-82` fails closed with a clear error | no |
| Frontends per service | 1 | `config.c:47-50` | yes (man:35) |
| Accepted packet size | 9000 B | `gredist.c:415` | yes (README:54) |
| Recv buffer | 65536 B stack (`BUF_SIZE`) | `gredist.c:347` | no |
| Service-name charset | `[A-Za-z0-9_.-]`, no `/`, no `..` | `gredist.c:262-263` | no |
| `MAX_FRONTENDS` | 4 | defined `gredist.h:16`, **never used** | n/a |
| Backend name length | 127, silently truncated | `config.c:85` `strncpy` with no length check (frontend is checked, backend is not) | no |
| Config line length | 511 | `config.c:29` `fgets`; a longer line is split and the tail is parsed as a new directive | no |

## Concurrency, ordering, persistence

- **Model**: one process, one thread, one service. Strictly sequential
  recv -> parse -> select -> sendto per packet. No batching, no parallelism, no
  worker pool.
- **Ordering**: packets are forwarded in receive order; nothing reorders.
- **Signals**: correct async-signal-safe use of `volatile sig_atomic_t` flags
  polled in the main loop (`gredist.c:67-71`).
- **Durability: none.** Every counter, every health state and every peer list
  lives in process memory. There is no state file, no write-ahead anything, and
  `/run/saphira/gredist/` is never created (C19). **A restart resets all
  statistics to zero** and re-marks all backends healthy.
- **Recovery**: there is nothing to reconcile. After a restart the daemon
  re-derives everything from the config file; the only persistent artefact in the
  entire system is the config file itself.

## Failure behaviour (as opposed to happy path)

- **No healthy backend** -> `dropped_no_backend`, packet lost. Documented (C22).
- **`sendto` failure of any kind** -> `dropped_queue`, packet lost, one log line
  per failure. An unreachable backend, a full qdisc and a genuine socket error are
  indistinguishable in the counters.
- **Malformed input** -> counted and dropped, no log line per packet, so a
  flood is invisible in the log.
- **Reload with a bad config** -> `load_config` fails, the old config is kept and
  the failure is logged. Sound.
- **`ping` missing** -> `probe_backend` child exits 127, every backend is marked
  down within ~4 s and the daemon drops everything. `iputils` is a declared
  runtime dependency, so this is contained, but a `PATH` that excludes `ping`
  silently disables the whole service.
- **Crash / kill** -> no state, no partial config, no cleanup. The `nft` table
  created at startup is **never removed**, so a crashed or replaced service
  leaves its empty `nat prerouting` chain behind forever.
- **Multi-service** -> independent processes, but each writes its own nft table;
  two services on one host are fully isolated in config, membership and stats,
  and share nothing except the host's routing table and the nft ruleset.

## Security / trust boundaries

- Raw sockets require `CAP_NET_RAW`; the daemon runs as **root for its entire
  lifetime** and never drops privilege (C7).
- **Shell interpretation of the `-c` config basename.** `gredist.c:268-274`
  derives the service name from the config path basename and applies **no**
  validation, unlike the positional service name which is charset-checked at
  262-263. `try_setup_nft` then interpolates that name into
  `system("nft list table inet saphira_gredist_%s ...")` (`gredist.c:148-157`).
  Any shell metacharacter or command substitution in the basename of a config
  path passed to `-c` is executed by `/bin/sh` as root. Proven on a disposable
  test node in P5; fixed independently of the privilege drop, by removing shell
  interpretation rather than by demoting the exploit.
- `system()` is also used for the `command -v nft` probe (`gredist.c:151`).
- No nftables rule is ever installed, so the firewall surface gredist adds is an
  empty chain — harmless today, but it is unowned, uncleaned, and would become
  live the moment the placeholder were filled in.

## Claims found unimplemented or contradicted (detail in RESULTS.md)

| Ref | Finding |
|-----|---------|
| C9  | The `nft` fast path is a placeholder. It creates a table and an empty `nat prerouting` chain and says so in its own log line. No DNAT, no fast path, no acceleration exists. |
| C19 | `/run/saphira/gredist/` is documented and never created; `DEFAULT_STATS_PATH` is dead code. |
| C13 | True for health-driven removal; false for a config-list edit, because the score includes the backend array index. |
| -  | The shipped `lab.sh` integration gate cannot fail: `do_run` ends with `echo` and `cleanup`, so it always exits 0, and `run-tests.sh` reports `LAB PASS` regardless. |

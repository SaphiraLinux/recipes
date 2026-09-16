# saphira-gredist

Protocol 47/GRE distributor for Saphira Linux.

```
client -- GRE (outer src=client dst=frontend, GRE header+inner) --> frontend -- rebuilt outer --> backend(s)
```

One host may run multiple independent named GRE services. Each service has exactly one frontend and one or more backends.

## Configuration

`/etc/saphira/gredist/<service>.conf`:

```
frontend=217.155.241.55
backend=172.16.10.10
backend=172.16.10.11
```

IPv6 uses same format:

```
frontend=2a02:8012:bc57::47
backend=2a02:8012:bc57:100::10
```

Mixed pools are supported (v4 frontend -> v6 backends, etc.). When families differ the outer IP envelope is terminated and rebuilt; GRE header and encapsulated payload are preserved unchanged.

## Running

```
gredist service_name        # loads /etc/saphira/gredist/service_name.conf
gredist -c /path/to.conf
gredist --syslog service_name
```

Requires `CAP_NET_RAW` (raw sockets for protocol 47) and usually `CAP_NET_ADMIN`. Log to stderr by default, `--syslog` to syslog.

Signals: `SIGHUP` reload config, `SIGUSR1` dump stats, `SIGTERM`/`SIGINT` exit.

## Design

- **Userspace control, kernel dataplane where practical**: userspace owns config, membership, health, stats and HRW policy. Kernel handles routing, optional `nft` fast-path (same-family DNAT via `inet` table `saphira_gredist_<name>`), and raw-socket I/O. Cross-family translation is always userspace-rebuilt outer header (kernel adds correct family header on send).

- **GRE parsing**: follows `net/ipv4/gre_demux.c:gre_parse_header` – validates 4-byte base, checks `GRE_VERSION`/`GRE_ROUTING`, computes `gre_calc_hlen` from `CSUM|KEY|SEQ`, fails closed on truncated claims, supports keyless and keyed (key is visible identifier, not secret). Malformed (version, routing, truncated option, fragment, oversized >9000) are dropped and counted.

- **Backend selection**: rendezvous/HRW hashing on `outer_src || gre_key`. Score = `splitmix64(fnv1a(backend_str) XOR flow_hash)`, pick max among healthy. Removal of a backend moves only its flows; surviving mappings remain stable; rejoin is deterministic.

- **Health**: active ICMP `ping -c1 -W1` per backend every 2s, 2 fails → down, 2 successes → up. Logs transitions. Forwarding to no healthy backend drops.

- **Forwarding**: receive via `AF_INET`/`AF_INET6` `SOCK_RAW` `IPPROTO_GRE` bound to frontend, strip outer IP, select backend, send via `AF_INET`/`AF_INET6` raw with `GRE+inner` payload to backend – kernel builds new outer header (v4 `tot_len`/`checksum`, v6 `payload_len`). Same-family preserves payload; cross-family rebuilds outer.

- **Queue pressure / loss / fragments**: RCVBUF 4MiB, `ENOBUFS` counts as queue drop, fragments detected via `frag_off`, loss simulated via harness netem.

## Building

```sh
make -C files/src              # -march=x86-64-v3
make -C files/src ARCH=native  # or ARCH= for generic
make -C files/src clean
make -C files/src install DESTDIR=/tmp/pkg
```

Requires only C11 and Linux headers, musl compatible.

```sh
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE src/gredist.c src/gre.c src/config.c -o gredist
```

## Test harness

Lab uses Linux netns (and OVS if available) to create isolated GRE environments.

```sh
sudo tests/lab.sh setup    # create namespaces, bridge, veths
sudo tests/lab.sh run      # runs exercises below
sudo tests/lab.sh cleanup

tests/run-tests.sh         # unit + integration without netns (requires raw)
```

Harness exercises:

- GRE over IPv4 → IPv4 backend
- GRE over IPv4 → IPv6 backend
- GRE over IPv6 → IPv4 backend
- GRE over IPv6 → IPv6 backend
- mixed-family pools
- keyed / keyless GRE
- backend removal / recovery / rapid flaps
- malformed/truncated, oversized, fragments, queue pressure, loss, affinity

See `tests/` for implementation.

## License

BUSL-1.1, Copyright (C) 2026 Saphira Linux. See `LICENSE`.

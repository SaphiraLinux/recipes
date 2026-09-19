Build a small standalone C program called saphira-proxyto.

Purpose
-------

saphira-proxyto is a generic TCP proxy for applications which do not
understand the HAProxy PROXY protocol.

It accepts a TCP connection carrying a valid PROXY protocol header,
parses and removes that header, connects to a configured local/backend
TCP service, then transparently forwards the remaining byte stream in
both directions.

It is deliberately application-independent. Geomyidae/Gopher is the
first use case, but the program must not contain Gopher-specific code.

Target
------

- Written in C.
- Must build cleanly against musl libc.
- No external library dependencies.
- Linux target.
- IPv4 and IPv6.
- No systemd-only assumptions.
- Do not daemonise; OpenRC/systemd will supervise it.
- Small, simple and auditable.
- No TLS, HTTP or application protocol parsing.
- No initramfs assumptions.

Invocation
----------

The intended invocation is:

    proxyto geomyidae

This loads:

    /etc/saphira/proxyto/geomyidae.conf

Configuration example:

    application=/usr/bin/geomyidae
    listen=172.16.0.2:70
    proxy=127.0.0.1:70

Meaning:

    application=
        Application associated with this proxy definition.
        Initially informational/validation only. proxyto does NOT launch
        or supervise the application.

    listen=
        Local IP address and TCP port on which proxyto accepts HAProxy
        PROXY-protocol connections.

    proxy=
        Backend IP address and TCP port to which the clean TCP stream
        is forwarded after the PROXY header has been removed.

Do not require listen and proxy ports to differ. This is valid:

    listen=172.16.0.2:70
    proxy=127.0.0.1:70

because they bind/connect different addresses.

Do not default to 0.0.0.0. The configured listen address must be used
exactly. IPv6 addresses must also be supported, with an unambiguous
configuration syntax.

PROXY protocol
--------------

Use the supplied HAProxy PROXY protocol specification as the normative
reference.

Support:

- PROXY protocol v1
- PROXY protocol v2
- TCP over IPv4
- TCP over IPv6
- LOCAL/UNKNOWN semantics where required by the specification

The complete PROXY header must be consumed before any application
payload is forwarded.

Malformed, incomplete or unsupported headers must cause the connection
to be rejected. Never pass a malformed PROXY header through to the
backend application.

Do not guess whether a connection is using PROXY protocol. The proxyto
listener is explicitly a PROXY-protocol listener.

Forwarding
----------

After parsing the header:

    client -> proxyto -> backend
    backend -> proxyto -> client

The application payload must be byte-for-byte unchanged.

Handle:

- partial reads
- partial writes
- EINTR
- connection close
- half-close where practical
- backend connection failure
- multiple simultaneous clients

Do not assume recv() returns the entire PROXY header in one call.

Logging
-------

proxyto knows the real client address from the PROXY header, so log it.

Useful connection log form:

    proxyto[pid]: geomyidae client=[2001:db8::1]:43122 backend=127.0.0.1:70 connected

and on close:

    proxyto[pid]: geomyidae client=[2001:db8::1]:43122 closed rx=42 tx=1937

Log startup/configuration errors clearly.

Important limitation
--------------------

The backend application will see proxyto's backend-side socket address,
for example 127.0.0.1, not the original client's address.

Do NOT implement transparent proxying, TPROXY, source-address spoofing,
routing tricks or application-specific client-IP injection in version 1.

The original client address is available in proxyto's logs.

Security
--------

The PROXY header is trusted metadata supplied by an upstream proxy.
The implementation must therefore be strict about header length,
address family, field sizes and bounds checking.

Do not use unsafe unbounded string functions.

The listener is expected to be protected by host firewall policy so
only the trusted HAProxy frontend can reach it. We can add an explicit
trusted_proxy= configuration option later if useful.

Repository layout
-----------------

    saphira-proxyto/
    ├── etc/
    │   └── saphira/
    │       └── proxyto/
    │           └── geomyidae.conf
    ├── src/
    │   ├── proxyto.c
    │   └── ...
    ├── usr/
    │   └── bin/
    ├── README.md
    └── Makefile

Build initially on Arch, but the source and Makefile must remain
musl-compatible. Do not rely on glibc-only APIs.

The first acceptance test is:

    HAProxy :70
        send-proxy / send-proxy-v2
            ->
    proxyto listening 172.16.0.2:70
            ->
    geomyidae listening 127.0.0.1:70

and a normal Gopher request must reach Geomyidae without any PROXY
header bytes leaking into its request stream.

## Privilege model

The daemon starts as root only to bind privileged ports such as
TCP/70. Startup order: parse and validate configuration, resolve and
bind the listening socket, listen(), resolve the dedicated
proxyto:proxyto account, permanently drop supplementary groups, gid
and uid (in that order), verify the drop stuck and privilege cannot
be regained (including a setuid(0) probe), then enter the
accept()/fork loop. All accepted connections and PROXY parsing run
as proxyto, never uid 0; forked workers inherit the dropped
identity. Any failure (missing account, failed setgroups/setgid/
setuid, regained privilege) is fatal. Started unprivileged, it logs
a notice and continues. No chroot yet (separate hardening step; it
complicates syslog and name resolution). The runtime account is
independent of any backend application account.

## Per-service tuning knobs

header_timeout=, connect_timeout= (milliseconds, 100..300000,
default 5000) and buffer_size= (bytes, 4096..1048576, default
16384, matching haproxy tune.bufsize). service_type= is a validated
backend label (default generic) used in logs, reserving the
namespace for future per-service relay tuning without complicating
the core loop. The small-segment v2 acceptance follows the PROXY
spec: reject only bytes that rule out both v1 and the v2 signature
prefix, otherwise wait for more.

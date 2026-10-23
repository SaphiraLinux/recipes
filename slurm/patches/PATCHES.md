# slurm patches

All five live in top-level `patches/`, so the builder worker applies
them automatically. Shared musl-port set (mirrored in
`slurm-accounting/patches/`): Slurm assumes glibc throughout.

| File | Why |
|---|---|
| `0001-callerid-musl-inet-nsap-addr.patch` | musl omits legacy BSD `inet_nsap_addr()`: static equivalent for plain-hex `/proc/net/tcp{,6}` parsing. |
| `0002-resolv-musl-res-n-apis.patch` | musl lacks `res_ninit`/`res_nsearch`/`res_nclose`: thin statics over classic `res_search` for SRV lookup. |
| `0003-namespace-linux-unistd.patch` | `sys/unistd.h` is glibc-only: use `unistd.h` (nothing exclusive used). |
| `0004-groups-musl-grent-pwent-r.patch` | musl lacks `getgrent_r`/`getpwent_r`: extend the `__APPLE__` plain fallback to non-glibc Linux. |
| `0005-macros-w-exitcode.patch` | `W_EXITCODE` is glibc-only: provide the glibc-identical construction for slurmstepd/srun. |

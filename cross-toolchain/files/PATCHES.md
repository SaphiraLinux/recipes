# cross-toolchain patches

| File | Why |
|---|---|
| `0001-aarch64-lp64-osdir-lib-not-lib64.patch` | AArch64 multilib osdir must be `/lib`, not `/lib64`: `/lib64` is forbidden on Saphira. |
| `0001-default-pthread-stack-1MiB.patch` | Same Saphira musl policy as native: default pthread stack 128 KiB → 1 MiB for the cross libc. |
| `0002-netinet-in6-kernel-uapi-coordination.patch` | Coordinate musl `netinet/in.h` with kernel UAPI `in6.h` so IPv6 structs are not redefined. |
| `0003-libc-compat-musl-netinet-in-coordination.patch` | Coordinate kernel `libc-compat.h` with musl's `_NETINET_IN_H` guard for the same redefinition class. |

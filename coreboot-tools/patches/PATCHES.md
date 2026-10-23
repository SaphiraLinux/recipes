# coreboot-tools patches

Top-level `patches/`, so the builder worker applies them automatically.

| File | Why |
|---|---|
| `bucts-sys-io.patch` | musl port: include `sys/io.h` on any Linux, not only `__GLIBC__`. Without it `bucts` misses `iopl`/`outb`. |
| `cbmem-endian-include.patch` | `cbmem.c` uses `le32toh`/`le16toh` without `endian.h`: glibc tolerated it, musl errors. Without it the build fails. |

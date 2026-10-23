# rp-pppoe patches

Top-level `patches/`, so the builder worker applies it automatically.

| File | Why |
|---|---|
| `0002-src-pppoe.h-fix-build-with-musl-libc.patch` | Buildroot backport (Fabrice Fontaine): reorder includes so libc `ethhdr` wins on musl. Without it the build fails. |

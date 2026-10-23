# libnvidia-container patches

| File | Why |
|---|---|
| `0001-musl-compat.patch` | musl port: guard glibc-only `gnu/lib-names.h` with a musl `LD_SO` path, plus `basename`/`secure_getenv`/signal.h fixes. Without it the build fails on musl. |

# libdaemon patches

| File | Why |
|---|---|
| `libdaemon-musl-unistd.patch` | Carried from cports/J. Krause: include `unistd.h`, not glibc-only `sys/unistd.h`, which musl lacks. Without it the build fails. |

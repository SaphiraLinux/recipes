# acpid patches

| File | Why |
|---|---|
| `saphira-musl-stat.patch` | musl has no `stat64`/`fstat64` family (`off_t` is already 64-bit). Use `stat`/`fstat` or the build fails. |

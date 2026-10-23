# unzip patches

Top-level `patches/`, so the builder worker applies it automatically.

| File | Why |
|---|---|
| `0001-musl-time-prototypes.patch` | Drop K&R `gmtime()`/`localtime()` redeclarations that clash with musl `time.h`. Without it the build fails on musl. |

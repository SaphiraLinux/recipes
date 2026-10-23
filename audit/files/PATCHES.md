# audit patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `0003-all-get-rid-of-strndupa.patch` | Backport (Tycho Andersen, 2017): replace the glibc-only `strndupa` with `alloca` plus `strncpy`. musl has no `strndupa`; without it the build fails. | Yes — it IS an upstream backport. |
| `fix-basename.patch` | Adapted from Alpine: define `basename` via `strrchr` so the musl build needs no `libgen.h`. Without it the build fails on musl. | Possibly, as a musl-compat contribution; carried from Alpine. |

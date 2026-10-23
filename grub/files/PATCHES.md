# grub patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `10_linux-saphira-branding.patch` | Saphira GRUB menu branding (classes, distributor, IDs). Never upstream. | No. |
| `musl-gnulib-sys-cdefs.patch` | musl port: guard the glibc-only `sys/cdefs.h` include with `__GLIBC__` and use gnulib fallbacks (musl ships no `sys/cdefs.h`). Without it grub does not compile on musl. | Possibly, as a gnulib/musl-compat contribution; not submitted. |

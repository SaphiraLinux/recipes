# grub patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `10_linux-saphira-branding.patch` | Saphira GRUB menu branding (classes, distributor, IDs). Rebased hunks 3-4 for 2.16 (menuentry/submenu ID lines gained `--allowed-user-list` context). Never upstream. | No. |
| `earlyfw-10-linux-discovery.patch` | Early-firmware discovery: firmware-only cpios named `earlyfw-<release>.img` produce initrd lines like the initramfs names stock 10_linux matches (listed first, so the current name wins over stale `initramfs-<release>.img` orphans). | No (Saphira-specific). |
| `10_linux-partuuid-fallback.patch` | No-initramfs root guard: the stock PARTUUID branch falls back to the device path when grub-probe finds no PARTUUID (MBR layouts), because a bare PARTUUID= is as unbootable as UUID= here. | No (Saphira policy). |

Dropped in 2.16: `musl-gnulib-sys-cdefs.patch` (guarded the glibc-only
`sys/cdefs.h` include with `__GLIBC__`). Upstream templated
`getopt-cdefs.in.h` with `@HAVE_SYS_CDEFS_H@`, so the hard-coded
`#if 1` is gone and the workaround is obsolete.

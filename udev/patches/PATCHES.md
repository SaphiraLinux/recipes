# udev patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. These live in
top-level `patches/`, so the builder worker applies them automatically
before `recipe_build` (no recipe command needed). See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `0001-systemd-261.2-saphira-meson-paths.patch` | Saphira executable layout: pins `mount`/`umount` to `/bin`, `kmod` to `/usr/bin` (where the kmod recipe installs it — a `/bin/kmod` pin here shipped a dead path, SEV1 2026-10-22), and resolves relative helper names under `/sbin` (every relative entry is sbin-class on Saphira). Without it the daemon carries merged-usr `/usr/bin` defaults that do not exist. Proven by dry-run against pristine 261.2. | No — Saphira layout. |
| `0002-systemd-261.2-saphira-root-runtime.patch` | Root runtime paths: `user@.service` uses the real systemd binary path, sysctl service uses the root libexec dir, and the `init` symlink installs at the real `/sbin` rather than `/usr/sbin`. Harmlessness is structural: the payload keep-list in `recipe.sh` discards everything outside the device-manager whitelist, so layout-only changes here cannot leak into the package. | No — Saphira layout. |
| `0003-systemd-261.2-saphira-udev-runtime.patch` | udev daemon + sysctl service at root-runtime paths with split `libexecdir` handling. Same containment as 0002: only whitelisted paths ship. | No — Saphira layout. |

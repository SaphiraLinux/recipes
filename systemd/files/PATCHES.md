# systemd patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `saphira-split-run.patch` | Split `/run` vs `/var/run`: upstream rewrites `/var/run` to `/run` in unit parsing, transient units, tmpfiles entries, taints a non-symlink `/var/run`, and recreates the alias via `tmpfiles.d/var.conf`. Saphira keeps both as separate real directories. Drop it and boot recreates the forbidden alias. | No — contradicts upstream's merged design. |
| `saphira-unmerged.patch` | Unmerged identity: sd-bus default follows the split `/run` (upstream pointed at merged `/run/dbus` while the daemon binds `/var/run/dbus`, causing the logind restart loop), plus an always-on `saphira-unmerged` taint naming the layout. Fails closed on upstream drift like the split-run patch. | No — Saphira identity patch. |
| `sysusers-static-ids.patch` | Pins the oom/coredump sysusers fixed IDs (the two static confs have no meson ID knob); five templated IDs pin via meson flags. Without it those identities get dynamic IDs and the account census drifts. | No — Saphira ID policy. |
| `vmlinux.h` | Not a patch: vendored BTF header the BPF programs bind to, verified against its sidecar in `recipe_build` so a tampered header cannot quietly change bindings. | N/A (pinned input). |

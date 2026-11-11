# systemd patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `saphira-split-run.patch` | Split `/run` vs `/var/run`: upstream rewrites `/var/run` to `/run` in unit parsing, transient units, tmpfiles entries, taints a non-symlink `/var/run`, and recreates the alias via `tmpfiles.d/var.conf`. Saphira keeps both as separate real directories. Drop it and boot recreates the forbidden alias. | No — contradicts upstream's merged design. |
| `saphira-unmerged.patch` | Unmerged identity: sd-bus default follows the split `/run` (upstream pointed at merged `/run/dbus` while the daemon binds `/var/run/dbus`, causing the logind restart loop), plus an always-on `saphira-unmerged` taint naming the layout. Fails closed on upstream drift like the split-run patch. | No — Saphira identity patch. |
| `sysusers-static-ids.patch` | Pins the oom/coredump sysusers fixed IDs (the two static confs have no meson ID knob); five templated IDs pin via meson flags. Without it those identities get dynamic IDs and the account census drifts. | No — Saphira ID policy. |
| `saphira-repart-no-cryptsetup.patch` | Guards repart helpers used only behind HAVE_LIBCRYPTSETUP. Written when Saphira had no libcryptsetup (dead definitions warned as unused); now transparent pass-throughs with cryptsetup 2.8.8 present, kept for the #if shape. Fails closed on upstream drift. | Upstream always builds with cryptsetup present; Saphira-only configuration history. |
| `saphira-test-link-abi-musl-libc.patch` | Adds bare `libc.so` to the ABI gate's libc allowlist: musl objects record that exact DT_NEEDED (readelf-proven), which matches neither `libc.so.*` nor the `libc.musl-` loader name, failing all 631 objects without it. Test-harness-only, nothing shipped. | Yes, as a musl-correctness fix (allowlist already models musl, just missed the bare soname). |
| `saphira-test-sandbox-exclusions.patch` | Skips registration of seven tests the rootless build namespace cannot run (bind-remount, loop devices, idmapping, PR_SET_MM, /etc/os-release-dependent chase/os-util/specifier); executables still build. Replaces positional test selection, which trips an unreproducible meson matcher error at ~1900 names. | No - Saphira sandbox shape, not an upstream defect. |
| `saphira-default-path-split-bin.patch` | Appends `:/sbin:/bin` to the split-/usr default PATH: Saphira's `/sbin` and `/bin` are real directories holding half the toolset, but upstream's default omits them (merged systems alias them into `/usr`), blinding `find_executable()` to every `/bin\|/sbin` helper. Payload change; without it `test-path-util` fails finding `/bin/touch`. | No — Saphira layout, upstream assumes merged-/usr. |
| `vmlinux.h` | Not a patch: vendored BTF header the BPF programs bind to, verified against its sidecar in `recipe_build` so a tampered header cannot quietly change bindings. | N/A (pinned input). |

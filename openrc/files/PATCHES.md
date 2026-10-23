# openrc patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `saphira-no-run-migration.patch` | Never migrate real `/var/run` and `/var/lock` into symlinks: upstream OpenRC does this on every boot (an empty real directory rmdirs cleanly, then gets symlinked — proven on a 0.2.1 guest that kept `/var/run -> /run` despite fhs-converge). Same patch class as systemd's split-run: the non-usrmerged split is policy. | No — contradicts upstream behavior. |
| `saphira-binfmt-paths.patch` | Two fixes in `sh/binfmt.sh.in`: (1) registration writes use `printf '%s'`, never `echo` — proven by strace 2026-10-23 that bash emits the trailing newline as a separate writev segment, the kernel runs `.write` once per segment, and the lone-newline retry fails EINVAL after the operation already succeeded, so every fragment printed a spurious failure at every boot while every registration worked; (2) fragment dirs listed without trailing slashes so diagnostics print `/usr/lib/binfmt.d/x.conf`, not `//x.conf`. No behavior change beyond correct reporting. | (1) possibly, as an upstream robustness fix; (2) cosmetic, unlikely. Neither submitted. |

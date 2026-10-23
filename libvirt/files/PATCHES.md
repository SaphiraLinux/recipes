# libvirt patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `0001-secret-init-use-bin-sh-non-usrmerged.patch` | Non-usrmerged interpreter: `/bin/sh`, no `/usr/bin/sh`. Saphira is deliberately non-usrmerged; the upstream unit assumed the merge. Without it the secret driver unit cannot execute. | No — Saphira layout. |

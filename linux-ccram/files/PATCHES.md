# linux-ccram patches

The patch SERIES is documented authoritatively in `SERIES-ORDER`
(same directory): which upstream backports apply in which order,
which are intentionally skipped (already in 7.2.9 or superseded by
`fwd/` forward-ports), and the Saphira-original `ccram/` stack. Read
that file before touching anything here. This note covers only the
non-series patches.

| File | Why | Upstreamable? |
|---|---|---|
| `x86-64-v3.patch` | x86-64-v3 microarchitecture baseline, 7.2.9-refreshed context, applied strict/fail-closed. Same Saphira platform policy as the main kernel lines. | No. |
| `ccram/ccram-12-double-release-fix.patch` | STALE/UNAPPLIED (2026-10-23): r12 single-ownership PTL double-release fix is present on disk but absent from `SERIES-ORDER`, so the applier never applies it. Either wire it into the series or remove the file; leaving a fix on disk that never ships is the worst option. | N/A until wired. |

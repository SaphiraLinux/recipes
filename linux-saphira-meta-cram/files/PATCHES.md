# linux-saphira-meta-cram patches

This recipe is disabled (test that should not be deployed). The patch
SERIES is documented authoritatively in `SERIES-ORDER` (same
directory), shared with `linux-ccram` (upstream private-memory +
CRAM-tier backports, `fwd/` forward-ports, intentional skips). This
note covers only the non-series patch.

| File | Why | Upstreamable? |
|---|---|---|
| `x86-64-v3.patch` | x86-64-v3 microarchitecture baseline, strict-gated. Same Saphira platform policy as the main kernel lines. | No. |

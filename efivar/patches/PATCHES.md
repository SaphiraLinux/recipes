# efivar patches

Top-level `patches/`, so the builder worker applies it automatically.

| File | Why |
|---|---|
| `no-march-native.patch` | Reproducibility/ABI: strip `HOST_MARCH=-march=native` so the build is not host-CPU-specific. Native flags would bake the builder's CPU into every binary. |

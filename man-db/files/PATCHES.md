# man-db patches

| File | Why |
|---|---|
| `musl-iconv-fallback.patch` | musl's iconv lacks some conversions glibc provides: fall back instead of failing. Without it man page conversion aborts where glibc converts. |

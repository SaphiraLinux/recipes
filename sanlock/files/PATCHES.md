# sanlock patches

| File | Why |
|---|---|
| `basename-include.patch` | `basename()` needs `libgen.h` on musl. Without it the build fails. |
| `c23.patch` | Modern-toolchain fixes (missing `string.h` et al.) for C23/gcc14. Without it the build fails. |

# cronie patches

| File | Why |
|---|---|
| `0001-load_entry-error_func-prototype-c23.patch` | Modern-toolchain fix: type `load_entry`'s `error_func` as `void(*)(const char *)`. C23/gcc16 promotes the incompatible-pointer-types mismatch from warning to error; without it the build fails. |

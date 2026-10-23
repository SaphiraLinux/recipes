# yajl patches

| File | Why |
|---|---|
| `cmake4-target-file.patch` | CMake ≥ 4 removed the `LOCATION` target property: use `$<TARGET_FILE:>` generator expressions. Without it the build fails on CMake 4+. |

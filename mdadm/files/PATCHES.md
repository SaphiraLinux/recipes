# mdadm patches

| File | Why |
|---|---|
| `0001-gcc16-unused-but-set-variable.patch` | Modern-toolchain fix: downgrade `-Wunused-but-set-variable` from error (Assemble.c, Detail.c trip it under gcc 16); `-Werror` otherwise intact. Env `CFLAGS` cannot carry this (Makefile assigns `CFLAGS` unconditionally). |

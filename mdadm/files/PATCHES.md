# mdadm patches

| File | Why |
|---|---|
| `0001-gcc16-unused-but-set-variable.patch` | Modern-toolchain fix: downgrade `-Wunused-but-set-variable` from error (Assemble.c, Detail.c trip it under gcc 16); `-Werror` otherwise intact. Env `CFLAGS` cannot carry this (Makefile assigns `CFLAGS` unconditionally). |
| `0003-missing-disk-index-clamp.patch` | gcc `-Werror=format-overflow`: `sprintf` of `" MISSING_%d"` into the 16-byte on-disk `disk.serial` with int-typed index. Clamp at six digits (unreachable: bounded by `num_members`) so gcc proves safety; `snprintf` would trade this for `-Wformat-truncation` errors. |
| `0004-install-via-path.patch` | Non-usrmerge path fix: `INSTALL = /usr/bin/install` → PATH lookup. Saphira coreutils is `--bindir=/bin`, so the absolute path fails install with Error 127; plain `install` resolves to `/bin/install`. |

Retired at 4.6 but kept in-tree: `0002-imsm-orom-signature-nonstring.patch`
(upstream 4.6 added the `nonstring` attribute to `imsm_orom.signature`
itself, so the patch no longer applies and is not in the build loop;
the file stays as the 4.4 record).

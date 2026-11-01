# cyrus-sasl patches

| File | Why |
|---|---|
| `gcc16-md5-casts.patch` | Adapted from Alpine/upstream PR #873: explicit casts for `MD5_memset` calls in saslauthd. gcc15/16 promote `-Wincompatible-pointer-types` to errors; without it the build fails. |
| `time-h-gcc14.patch` | gcc14 build fix: add the missing `time.h` include in `plugins/cram.c`, drop a redundant one in `lib/saslutil.c`. Without it the build fails on gcc14+. |
| `gcc16-signal-handler-casts.patch` | gcc16: cast `void(*)(void)` handlers to `sa_handler` type at three assignments (behavior unchanged). Env `CFLAGS` cannot carry `-Wno-error` here (configure overwrites it). |

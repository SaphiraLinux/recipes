# vsftpd patches

| File | Why |
|---|---|
| `saphira-musl.patch` | musl compat: drop `-Werror` and force-include a header defining `WTMPX_FILE`, or the build fails on musl. |

# vpopmail patches

| File | Why |
|---|---|
| `saphira-rootless.patch` | Rootless staging: do not require host qmail binaries at configure time when `SAPHIRA_NO_HOST_DIRS=1` (qmail builds later in Saphira's order). Without it configure demands a live qmail system. |

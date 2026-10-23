# wireless-tools patches

| File | Why |
|---|---|
| `fix_iwlist_scanning.patch` | Arch backport (marked From Upstream): cap `iwlist` scan buffer growth at 65535. Without it scans with many networks print nothing. Applied conditionally by the recipe. |

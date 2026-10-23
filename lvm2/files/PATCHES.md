# lvm2 patches

| File | Why |
|---|---|
| `musl-stdio-assign.patch` | musl stdio fix (`freopen` plus `__GLIBC__` guards): without it every LVM tool segfaulted after fd setup (proven by strace). |

# openwsman patches

| File | Why |
|---|---|
| `musl-pthread-np.patch` | Provide `PTHREAD_MUTEX_RECURSIVE_NP` on musl (glibc extension, identical value). Saphira builds musl-only; without it the build fails. |

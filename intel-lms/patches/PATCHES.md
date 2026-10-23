# intel-lms patches

All six live in top-level `patches/`, so the builder worker applies
them automatically. All are musl ports: Intel's tree assumes glibc.

| File | Why |
|---|---|
| `musl-dt-unknown-enum.patch` | Undef musl's `DT_UNKNOWN` macro, which collides with a CIM DateTimeType enum identifier. |
| `musl-handle-null-cast.patch` | `HANDLE` is `int`: cast `0`, not `NULL`/`nullptr`, for device notification. |
| `musl-res-ninit-adapterlist.patch` | musl lacks `res_ninit`: snapshot global `_res` via `res_init` for adapter-list DNS reads. |
| `musl-res-ninit-syncnetwork.patch` | Same `res_ninit` shim for sync-network DNS state. |
| `musl-strerror-r-xsi.patch` | Handle the XSI (int-returning) vs GNU (char*-returning) `strerror_r` variants on musl. |
| `openwsman-musl-recursive-mutex.patch` | musl lacks `PTHREAD_MUTEX_RECURSIVE_NP`: map to POSIX `PTHREAD_MUTEX_RECURSIVE`. |

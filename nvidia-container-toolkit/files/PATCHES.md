# nvidia-container-toolkit patches

| File | Why |
|---|---|
| `0001-musl-go-nvml.patch` | musl `dlfcn` lacks `RTLD_DEEPBIND`/`RTLD_DI_ORIGIN` and rejects `ORIGIN`: remove the dead uses. Without it the Go NVML binding does not compile on musl. |

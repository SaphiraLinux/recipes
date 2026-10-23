# rpm patches

| File | Why |
|---|---|
| `rpm-musl-glob.patch` | musl has no `GLOB_BRACE`: degrade the flag to a no-op instead of failing the build (`GLOB_TILDE` untouched). |

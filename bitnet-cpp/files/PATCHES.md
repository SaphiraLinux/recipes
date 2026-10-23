# bitnet-cpp patches

| File | Why |
|---|---|
| `0001-saphira-build-banner.patch` | The vendored tree has no git metadata: replace the git-derived version banner with the Saphira build banner. |
| `0002-saphira-helper-entrypoints.patch` | Helpers resolve packaged llama binaries via `PATH`, with a local build-tree fallback. |

# emscripten patches

These live at the recipe root (not `files/` or `patches/`) and are
applied explicitly by `recipe.sh:69-71` via stdin redirect.

| File | Why |
|---|---|
| `deterministic-macro-paths.patch` | Reproducibility: map source/sysroot paths to a deterministic prefix in file/macro-prefix-map and debug dir. Without it builds embed builder paths. |
| `offline-ports.patch` | Saphira offline policy: make ports `retrieve()` fail loudly instead of fetching from a remote server. The tree vendors its ports; network fetch at build time is forbidden. |

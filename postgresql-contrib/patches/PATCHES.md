# postgresql-contrib patches

Top-level `patches/`, so the builder worker applies it automatically.

| File | Why |
|---|---|
| `configure-cache-cmp.patch` | Use `cmp -s` instead of `diff` for the configure cache-file comparison. (Same file is duplicated in `libpq/`, `newt/` and sibling `postgresql-*/patches/` dirs; each recipe carries its own copy.) |

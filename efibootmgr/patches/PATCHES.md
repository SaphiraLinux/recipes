# efibootmgr patches

Top-level `patches/`, so the builder worker applies it automatically.

| File | Why |
|---|---|
| `musl-gettext.patch` | musl port: stub gettext/dgettext macros to identity and drop libintl/setlocale. musl has no gettext; without it the build fails. |

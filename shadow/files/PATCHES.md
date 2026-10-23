# shadow patches

| File | Why |
|---|---|
| `0001-saphira-prefer-libxcrypt.patch` | Prefer libxcrypt explicitly (`-lxcrypt` with the libxcrypt include dir first): generic `-lcrypt` is musl's empty archive (Saphira crypt policy). Without both halves shadow silently builds against musl's crypt — or fails to build at all. |

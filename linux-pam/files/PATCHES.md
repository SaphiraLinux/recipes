# linux-pam patches

| File | Why |
|---|---|
| `0001-saphira-require-libxcrypt.patch` | Require libxcrypt explicitly: generic `-lcrypt` is musl's empty archive resolving into libc (Saphira crypt policy — see `saphira-packager/tests/crypt-ownership.sh`). Without it PAM links the wrong crypt. |

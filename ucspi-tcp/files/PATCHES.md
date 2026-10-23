# ucspi-tcp patches

| File | Why |
|---|---|
| `saphira-port.patch` | Modernize 1980s K&R C for current GCC/musl (implicit-int `main`, missing `errno.h` include). Without it the build fails. Saphira port. |

# netcat-openbsd patches

| File | Why |
|---|---|
| `musl-b64-resolv.patch` | musl has no libresolv: bundle a base64 codec and drop the `-lresolv` link. Without it the link fails. |
| `musl-iptos-va.patch` | musl's `netinet/ip.h` lacks glibc-only `IPTOS_DSCP_VA`: define it. Without it the build fails. |

# qmail patches

| File | Why |
|---|---|
| `saphira-staging.patch` | Rootless staging: fixed build-time identities via the `accounts.d` fragment instead of requiring host qmail users at configure time. Without it the build demands a live qmail system. Saphira-specific. |

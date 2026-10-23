# bind patches

| File | Why |
|---|---|
| `saphira-default-conffile.patch` | Default conffile moves from `${sysconfdir}/named.conf` to `${sysconfdir}/bind/named.conf`: no configure knob exists for it, and the packaged layout keeps BIND configuration under `/etc/bind`. Without it the daemon looks in the wrong place. |

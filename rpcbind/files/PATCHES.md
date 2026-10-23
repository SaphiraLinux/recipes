# rpcbind patches

| File | Why |
|---|---|
| `rpcbind-run-lock.patch` | Split-`/run` layout: upstream hardcodes the lock at `/run/rpcbind.lock` with no knob; move it beside the package's `/var/run` state. Without it the lock lands in the wrong tree. |

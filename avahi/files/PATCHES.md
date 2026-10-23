# avahi patches

| File | Why |
|---|---|
| `avahi-saphira-runstatedir.patch` | Split-`/run` layout: upstream hardcodes the daemon runtime dir at `/run` with no knob; Saphira keeps `/var/run` as the packaged-daemon runtime tree. Without it the daemon writes where the layout does not expect. |

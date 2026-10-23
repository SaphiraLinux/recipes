# kea patches

| File | Why |
|---|---|
| `0001-asio-deadline-timer-to-steady-timer.patch` | Boost ≥1.87 removed `asio::deadline_timer`: migrate to `steady_timer`. Saphira port (not an upstream backport), verified `-Np1`. Without it the build fails against current Boost. |

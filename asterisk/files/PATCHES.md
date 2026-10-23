# asterisk patches

Six musl-port and locking fixes, applied in order by the recipe loop.
The five `recursive-*` patches share one shape: upstream requires
recursive mutex semantics but the static initializers are
non-recursive on Linux, so re-entrant paths self-deadlock (proven at
boot/load: zero modules loaded, config reload hangs). Each makes the
named lock recursive; none changes lock ordering.

| File | Why |
|---|---|
| `0001-ast_expr2-musl-sys-cdefs-__P.patch` | musl ships no `sys/cdefs.h`: define a fallback `__P(x)` macro or the bison parser fails with syntax/implicit-declaration errors. |
| `0002-loader-recursive-module_list-lock.patch` | `module_list.lock` recursive: boot self-deadlocks with zero modules loaded otherwise. |
| `0003-pbx-recursive-conlock.patch` | `conlock` recursive: re-entrant PBX paths self-deadlock otherwise. |
| `0004-unistim-recursive-devicelock.patch` | `devicelock` recursive: reload via `finish_bookmark` self-deadlocks otherwise. |
| `0005-prometheus-recursive-scrape_lock.patch` | `scrape_lock` recursive: post-apply unregister retaking it self-deadlocks otherwise. |
| `0006-config-recursive-cfmtime_head.patch` | `cfmtime_head.lock` recursive via config init: include recheck self-deadlocks otherwise. |

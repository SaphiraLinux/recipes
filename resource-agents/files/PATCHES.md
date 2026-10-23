# resource-agents patches

ldirectord IPv6-first series, applied in order by the recipe loop.
Each hardens one layer of IPv6 handling; together they make ldirectord
correct on IPv6 literals and mapped addresses.

| File | Why |
|---|---|
| `0001-ldirectord-make-Socket6-optional-and-fall-back-to-core.patch` | Make Socket6 optional with a core-module fallback instead of failing where it is absent. |
| `0002-ldirectord-degrade-gracefully-when-non-core-check-mod.patch` | Minimal HTTP check when the LWP chain is absent instead of failing. |
| `0003-ldirectord-harden-IPv6-address-parsing-and-ipvsadm-r.patch` | Harden IPv6 literal-vs-port parsing in ipvsadm output readers. |
| `0004-ldirectord-accept-IPv4-mapped-IPv6-literals.patch` | Accept IPv4-mapped IPv6 literals consistently across dotless character classes. |

# pppd patches

Top-level `patches/`, so the builder worker applies it automatically
(documented in `recipe.sh:38-39` alongside the seds that must run
before `./configure`, since classic configure bakes `Makefile.linux`
at generation time).

| File | Why |
|---|---|
| `ppp-2.4.5-plugin-musl.patch` | Bundled rp-pppoe plugin musl fix (`sys/cdefs.h`, ethhdr include order, unused `if_pppox` include). Without it the plugin does not compile on musl. |

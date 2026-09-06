# Saphira Linux recipes

Native package recipes for [Saphira Linux](https://github.com/SaphiraLinux): a musl-libc based
source-built distribution with a clean `/lib` + `/usr/lib` filesystem layout (no `/lib64`,
no `/usr/lib64`, no usrmerge).

## Layout

Each package is one directory:

```
<package>/
  recipe.sh        # metadata (name, version, deps, license) + recipe_build() / recipe_install()
  files/           # patches, init scripts, service units, configs shipped with the package
```

Shared tooling and the recipe contract live under `saphira-packager/`; `package-template/`
is the starting point for new recipes.

## Sources

Upstream source archives are not stored in this repository. Each recipe.sh pins its sources and verifies them by SHA-256. Sources are fetched when required and stored in Saphira’s content-addressed verified source cache, so subsequent builds can reuse the verified archive without downloading it again. To build from this checkout you need the Saphira builder controller.

## Contributing

One commit per package change, lowercase `area: summary` message (e.g.
`packager: require exact failed marker for retries`). No `r0` packages: every recipe
ships `pkgrel>=1`.

## License

We’ve made a small licensing change to software written specifically for Saphira Linux.

Saphira remains FREE — including commercial use.

Run your business on it. Host customers on it. Run commercial workloads, managed infrastructure or SaaS on it. Make money using Saphira. None of that costs you a licence fee.

What has changed is the licence on code that AKADATA wrote specifically for Saphira. That code can no longer simply be lifted out, rebadged and turned into somebody else’s commercial product or service without talking to us first.

We’ve chosen Business Source License 1.1 for those components. After four years, each released version transitions to GPL-2.0-or-later.

Upstream software keeps its upstream licence. Previously released MIT versions remain MIT.

Use Saphira commercially: FREE.
Commercialise Saphira-owned code outside Saphira: talk to AKADATA.

That feels like the right balance.

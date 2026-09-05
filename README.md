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

Upstream source archives are **not stored in this repository**. Each `recipe.sh` pins its
sources and verifies them by sha256; archives are resolved at build time from the local
source mirror. To build from this checkout you need the Saphira builder controller and a
populated source mirror.

## Contributing

One commit per package change, lowercase `area: summary` message (e.g.
`packager: require exact failed marker for retries`). No `r0` packages: every recipe
ships `pkgrel>=1`.

## License

MIT — see [LICENSE](LICENSE).

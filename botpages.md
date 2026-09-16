# Bot-challenge pages served to Egg egress

Sources below serve HTML challenges instead of archives when fetched from
Egg. Download manually on a capable host and drop the files in place of
the failed fetch, then update the recipe `sha256` if your copy differs.

| Host | Blocked path | Working alternative |
|---|---|---|
| cmake.org | https://cmake.org/files/ | https://github.com/Kitware/CMake/archive/refs/tags/v<ver>.tar.gz |

## Egress notes (verified 2026-08-26/27)

- `ftp.gnu.org` intermittently returns 404/challenge pages for some paths
  (nettle, libtasn1 at the time); other GNU packages fetched fine earlier.
  Retry or use project-specific mirrors.
- `lysator.liu.se` flaky: nettle tarball came back as an error page after
  an initially successful probe.
- GitHub release/archive tags generally work; exceptions: the `lua/lua`
  v5.4.8 tag is a bare development snapshot without makefile — use the
  official https://www.lua.org/ftp/lua-5.4.8.tar.gz instead.
- `www.lua.org`, `nginx.org`, `www.php.net`, `dovecot.org`,
  `gitlab.com` release archives all fetched clean.

Manual-download placement: sources are consumed by `buildpkg` from the
recipe-declared `source=` URL through its normal fetch path; stage the
tarball into the build workspace source archive location or re-run the
build once egress cooperates.
| ftp.astron.com | TLS cert mismatch (wrong hostname cert) | file-5.48 source; github FILE5_48 snapshot lacks generated configure; Debian pool stops at 5.47 | retry later or use autoreconf snapshot |
| ftp.rpm.org | TLS cert mismatch | popt-1.19 release tarball | use github tag + autoreconf, or another mirror |

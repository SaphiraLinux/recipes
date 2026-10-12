# Provenance: saphira-proxyto v0.1.0 tag archive

Two authorities, kept separate:

- The SaphiraLinux/saphira-proxyto repository is the source of truth
  (currently private). No generated tarball is committed there.
- This directory carries the vendored copy Saphira's vendored-source
  policy requires, so `/recipes` builds reproducibly without network
  access to the private repo.

- Tag: `v0.1.0` (source home for the 0.1.0 line).
- Recipe URL (canonical, upstream-style):
  `https://github.com/SaphiraLinux/saphira-proxyto/archive/refs/tags/v0.1.0.tar.gz`
- Vendored file: `files/v0.1.0.tar.gz` — packed with `git archive`
  from the pushed tag (not downloaded: codeload refuses anonymous
  fetch for the private repo), SHA256:
  `fc401949c504a26305a2e67e48e13f8b819d73008e51af0f55d14f0ae10e6a17`
  (see `v0.1.0.tar.gz.sha256`; the worker re-verifies on every build).
- Archive root is a single top-level `saphira-proxyto-0.1.0/`
  directory, which the worker flattens into `$SRC`, so the recipe
  builds `$SRC/Makefile` and `$SRC/src` directly.

If the repo ever goes public, re-verify this pin against the
codeload bytes before deleting the vendored copy.

The packaged licence (`files/LICENSE`, installed to
`/usr/share/licenses/saphira-proxyto/LICENSE`) is the packaging copy
of the canonical `LICENSE` at the project repo root; canonical wins
on any divergence.

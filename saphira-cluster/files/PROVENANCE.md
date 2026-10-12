# Provenance: saphira-cluster v0.1.0 tag archive

Two authorities, kept separate:

- The saphira-cluster project repo is the source of truth. The
  project GitHub repository stays clean — no generated source
  tarball is committed there.
- This directory carries the vendored copy Saphira's
  vendored-source policy requires, so `/recipes` builds
  reproducibly even if GitHub is unavailable later.

- Tag: `v0.1.0` on project commit
  `bba9423144d75946d9e8389236d39fe0fe92ca94`
  ("cluster: BUSL-1.1 licensing for AKADATA-owned sources").
- Recipe URL (canonical, upstream-style):
  `https://github.com/SaphiraLinux/saphira-cluster/archive/refs/tags/v0.1.0.tar.gz`
- Vendored file: `files/v0.1.0.tar.gz` — the exact downloaded bytes
  (re-downloaded and byte-compared before vendoring), SHA256:
  `22f1154c1bf0e02aefc6d7fe52a864de234f91bbe51436016f60e6018d9898f1`
  (see `v0.1.0.tar.gz.sha256`; the worker re-verifies on every build).
- Archive root is a single top-level `saphira-cluster-0.1.0/`
  directory, which the worker flattens into `$SRC`, so the recipe
  builds `$SRC` directly (same flattening that saphira-garden's
  disabled reason documents).

The packaged licence summary (`files/LICENCE-summary.txt`, installed
to `/usr/share/licenses/saphira-cluster/LICENSE.txt`) is derived from
the canonical `LICENCE-summary.txt` at the project repo root; the
derivative carries a header line saying so. Canonical copy wins on any
divergence.

New source release = new tag + refreshed vendored bytes + new
URL/sha256 pin (+ `pkgrel` reset per unpublished/published state at
the time). The recipe publishes an APK; it never publishes a source
archive.

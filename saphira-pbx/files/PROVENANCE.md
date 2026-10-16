# Provenance: saphira-pbx v0.2.0 tag archive

Two authorities, kept separate:

- The saphira-pbx project repo is the source of truth. The
  project GitHub repository stays clean — no generated source
  tarball is committed there.
- This directory carries the vendored copy Saphira's
  vendored-source policy requires, so `/recipes` builds
  reproducibly even if GitHub is unavailable later.

- Tag: `v0.2.0` on project commit
  `ab0404899361ef1dbb6117297162926d60f3c361`
  ("pbx: MCP network transport, TLS/certbot, token recovery show,
  scope-all"). Feature release: real `mcp serve` transport, TLS
  handling and `tls-check`, Certbot lifecycle with
  validate-before-stage, token recovery show, scope-all expansion,
  ncurses TUI, voicemail PINs (schema v4).
- Recipe URL (canonical, upstream-style):
  `https://github.com/SaphiraLinux/saphira-pbx/archive/refs/tags/v0.2.0.tar.gz`
- Vendored file: `files/v0.2.0.tar.gz`, SHA256:
  `46aa03bcf0f39114430082e5449eed571c59a43509f7ef29444a496d9a6c8790`
  (see `v0.2.0.tar.gz.sha256`; the worker re-verifies on every build).
  - Byte method: GitHub-generated tarball bytes, fetched 2026-10-12
    via the authenticated API tarball endpoint (`gh api
    repos/SaphiraLinux/saphira-pbx/tarball/v0.2.0` as akadata)
    because the repo was private at release time (unauthenticated
    codeload and repo page both 404; the environment gained gh auth
    since the v0.1.3 release, which had no authenticated path).
    Decompressed content byte-compared identical against local
    `git archive` of the tag (the tested tree, suite 156/156).
  - Archive root naming differs from the codeload convention:
    this endpoint roots at
    `SaphiraLinux-saphira-pbx-ab04048.../` where codeload would
    root at `saphira-pbx-0.2.0/`. Content is identical; the worker
    flattens any single top-level dir into `$SRC`, so the recipe
    builds `$SRC` directly either way. If the repo later goes
    public, codeload gzip framing (and root name) may differ from
    these bytes despite identical content — re-verify then per the
    v0.1.3 lesson, never assume byte stability.

The packaged licence summary (`files/LICENCE-summary.txt`, installed
to `/usr/share/licenses/saphira-pbx/LICENSE.txt`) is derived from
the canonical `LICENCE-summary.txt` at the project repo root; the
derivative carries a header line saying so. Canonical copy wins on any
divergence.

# saphira-gopher-publish

Markdown to Gopher, for Saphira Linux.

`saphira-gopher-publish` walks the Markdown representation of a website and
generates a complete Gopher tree suitable for geomyidae 0.99
(gophermap + index.gph). The website is the API for its Gopher edition: the
tool does not know how the site is built, only that it serves
`sitemap.xml` and honours `Accept: text/markdown`.

```
website --build--> https://example.org/
        -- Accept: text/markdown --> saphira-gopher-publish
        --> out/ --rsync --delete--> /srv/gopher/
        --> gopher://gopher.example.org/
```

## Why

Saphira's packaging philosophy applies to publishing too: remember the past.
Gopher (RFC 1436, 1991) is the web without the influence economy.

No faces competing for attention. No autoplay. No visual noise. No
algorithmic feed. Just menus, links, files and words — and the words have to
stand on their own. Text is cheap to serve forever, renders on anything from
a terminal to a phone, and cannot be hijacked by a voice or a face. Serving
it is nearly free; reading it is what the medium was for.

This package exists so a Saphira system can present any Markdown-speaking
website as a first-class Gopher site — automatically, deterministically, and
with no third-party service in between.

## Gopher hosting: one site per address

Classic Gopher has no HTTP-style `Host:` header, so there is no name-based
virtual hosting on a shared IP:port. In normal deployment, one IP:port
identifies one Gopher site. Multiple addresses solve that cleanly; IPv6
makes assigning one address per hostname particularly easy. Plan DNS
accordingly: a Gopher hostname needs an address of its own (TLS/SNI is not
part of plain Gopher on TCP/70 and does not change this picture).

## How it works

Sitemap-driven: fetch `sitemap.xml`, then GET each URL with
`Accept: text/markdown`. Markdown links are used for relationship
(external `h` entries) not for discovery. Same-origin redirects only;
fail loudly on malformed or unreachable source.

Python 3, stdlib only. Deterministic output, atomic replacement, bounded
timeout. Regenerate at will; stale entries are never appended.

Output is geomyidae 0.99:

- text leaves: `out/about.txt`, `out/rtfm/packages.txt`, `out/index.txt` (for `/`)
- every directory gets **both** `out/**/gophermap` (classic) and `out/**/index.gph`
  (native) with identical entries:

  Classic `gophermap` (host/port empty — geomyidae fills):
  ```
  1Documentation	/docs
  0About	/about.txt
  hWebsite	URL:https://example.org/
  ```

  Native `index.gph`:
  ```
  [1|Display|/dir/|host|port]
  [0|Display|/file.txt|host|port]
  [h|Display|URL:https://…|host|port]
  ```
  Escaping: `|` as `\|` in native display, tabs stripped in classic;
  geomyidae handles the wire protocol.

## Usage

Installed as `/usr/bin/saphira-gopher-publish`.

```sh
# Via config (all options in file, CLI overrides)
saphira-gopher-publish --dry-run
saphira-gopher-publish                # uses /etc/saphira/gopher-publisher.conf

# Explicit positional (config fallback)
saphira-gopher-publish https://example.org/ out --dry-run

# Build (config provides root_url/output_dir/root_include)
saphira-gopher-publish

# Overrides
saphira-gopher-publish https://example.org/ out \
    --gopher-host gopher.example.org --gopher-port 70 --timeout 10
saphira-gopher-publish out --root-include /srv/gopher-source/root-menu.include

saphira-gopher-publish --help
```

`--dry-run` / `--validate` fetch and build the full inventory without
writing anything — use it to prove the source contract before publishing.

Root homepage (`/` selector) is the menu itself. An optional
`--root-include FILE` (classic `gophermap` lines) is prepended to the root
menu only and de-duplicated. The package ships only the parser/support; the
curated navigation and site voice stay site-owned
(`/srv/gopher-source/root-menu.include`), never baked into the tool.

## Configuration

`/etc/saphira/gopher-publisher.conf` (installed) and
`gopher/etc/saphira/gopher-publisher.conf` (next to `bin`, dev) are checked
in order; `--config FILE` overrides. All options are available in the file
(`--help` shows CLI equivalents):

```ini
[gopher]
root_url = https://example.org/
output_dir = /srv/gopher
gopher_host = gopher.example.org
gopher_port = 70
timeout = 10
root_include = /srv/gopher-source/root-menu.include
user = gopher
group = gopher
```

`root_url` / `output_dir` may be omitted on CLI when set in config.
Generated output is chowned to `user:group` (`gopher:gopher`) when run as
root (best-effort on dev where the user does not exist).

## State that survives upgrades

Two paths are operator/site state:

- `/etc/saphira/gopher-publisher.conf` — configuration. Covered by apk's
  default `+etc` protection: local edits win on upgrade, package changes
  land as `.apk-new`.
- `/srv/gopher-source/root-menu.include` — seeded site content. The package
  ships an `/etc/apk/protected_paths.d/saphira-gopher-publish` entry
  (`+srv/gopher-source`) so a customised root menu is never overwritten
  during an upgrade; package updates land as `.apk-new` alongside it.

Generated output (the Gopher tree itself) is disposable: regenerate at any
time, never edit.

## Publish

```sh
rsync -a --delete out/ /srv/gopher/
```

`gopher://your-host/` is served from `/srv/gopher/` by geomyidae 0.99.
End-to-end check:

```sh
lynx gopher://your-host/
```

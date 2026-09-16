# saphira-mergetool

Resolve apk `.apk-new` files after upgrades.

When apk upgrades a **protected** file (everything under `/etc`, plus any
tree covered by `/etc/apk/protected_paths.d`) and the installed copy was
locally modified, the new package version lands beside the original as
`FILE.apk-new`. Nothing is applied automatically — the operator decides.
This tool makes that decision easy: scan, diff, then accept, keep, or
merge hunk by hunk.

```
apk upgrade
  -> /etc/init.d/saphira-build            (your modified version, kept)
  -> /etc/init.d/saphira-build.apk-new    (the new package version)

saphira-mergetool                         # what is pending?
saphira-mergetool --diff                  # every difference
saphira-mergetool --merge /etc/conf.d/saphira-build.apk-new
saphira-mergetool --accept all
```

## Actions

- **accept** — the `.apk-new` version replaces the installed file (the
  package's new content wins; an orphan `.apk-new` whose original is gone
  is promoted to the real name).
- **keep** — the installed file stays; the `.apk-new` is discarded.
- **merge** — interactive, hunk by hunk: `[y]` take the new hunk, `[n]`
  keep the old hunk as-is, `[a]` take all remaining hunks, `[q]` abort
  (nothing written, `.apk-new` kept for later). Local edits are preserved
  for every hunk you decline; mode and ownership follow the installed
  file.

Every action also runs under `--dry-run`.

## Configuration

`/etc/saphira/mergetool.conf` (CLI overrides):

```ini
[mergetool]
scan_paths = /etc /srv/gopher-source

[policy]
# fnmatch globs -> non-interactive resolution for --auto
/etc/init.d/* = accept
/etc/conf.d/* = keep
```

With `--auto`, configured policies are applied and unmatched files are
prompted for on a terminal (or reported as pending in scripts).

## Contract

- Never deletes an installed original.
- Refuses to run against files that are not `.apk-new` artifacts.
- Scan roots are configurable; the tool touches nothing outside them.
- Python 3, stdlib only.

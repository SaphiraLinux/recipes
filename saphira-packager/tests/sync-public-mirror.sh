#!/bin/sh

# sync-public-mirror tests: deterministic text-only export, named
# exclusion, and the fail-closed leakage gate. Fully hermetic: fixture
# source repo, fixture live repo, fixture public clone under SAPHIRA_TMPDIR.
# Never touches /recipes, /out, remotes, or signing keys.
#
# usage: sync-public-mirror.sh SYNC-PUBLIC-MIRROR

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s SYNC-PUBLIC-MIRROR\n' "$0" >&2
	exit 1
}

sync=$1
test_tmp_base=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-sync-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'chmod -R u+rwX "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT HUP INT TERM

# --- unit level: archive filter + variable expansion (no git needed) ------
python3 - "$sync" <<'PY'
import importlib.machinery
import importlib.util
import sys

spec = importlib.util.spec_from_loader(
    "sync_under_test",
    importlib.machinery.SourceFileLoader("sync_under_test", sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

archive = module.is_archive
assert archive("a.tar.gz") and archive("a.tgz") and archive("a.tar.xz")
assert archive("a.tar.bz2") and archive("a.whl") and archive("a.bin")
assert archive("a.gem") and archive("a.zip") and archive("A.TAR.GZ")
assert not archive("a.patch") and not archive("a.initd")
assert not archive("a.tar.gz.sha256") and not archive("a.tar.gz.asc")
assert not archive("a.sh") and not archive("recipe.sh")

# Payload excludes: canonical cert + usb.ids by basename (covers legacy
# per-recipe copies and the single canonical alike).
assert module.is_payload_excluded("wireless-regdb/files/saphira-regdb.x509")
assert module.is_payload_excluded("saphira-kernel/files/saphira-regdb.x509")
assert module.is_payload_excluded("hwdata/files/usb.ids")
assert not module.is_payload_excluded("good-pkg/files/fix.patch")
assert not module.is_payload_excluded("good-pkg/recipe.sh")

# Content magic: gzip masters / tag snapshots are archives even with
# misleading or missing extensions; DER/latin-1 are not archives
# (they are barred by payload excludes, not by magic).
assert module.content_kind(b"\x1f\x8b\x08\x00\x00\x00") == "archive"
assert module.content_kind(b"BZh91AY&SY") == "archive"
assert module.content_kind(b"\x7fELF\x02\x01") == "elf"
assert module.content_kind(b"\x30\x82\x05\xf5") == ""
assert module.content_kind(b"#\n#\tList") == ""

# Private patterns: keeper-colon/git-at fail closed, with the single
# operator-accepted shampoo exception.
assert ("keeper" + ":") in module.PRIVATE_PATTERNS
assert ("git" + "@") in module.PRIVATE_PATTERNS
assert ("git" + "@github.com:SaphiraLinux/shampoo.git") in module.PRIVATE_PATTERN_EXCEPTIONS

expand = module.expand_vars
assert expand("v${pkgver}.tar.gz", {"pkgver": "1.0"}) == "v1.0.tar.gz"
assert expand("v$pkgver.tar.gz", {"pkgver": "1.0"}) == "v1.0.tar.gz"
assert expand("${MISSING:-7.2.2}", {}) == "7.2.2"
assert expand("plain", {}) == "plain"
assert module.split_nvr("foo-1.0-r2.apk") == ("foo", "1.0", 2)
assert module.split_nvr("not-an-nvr") is None
print("unit: OK")
PY

# --- fixture source tree (git) --------------------------------------------
src=$test_root/src
mkdir -p "$src/good-pkg/files" "$src/withheld-pkg/files" "$src/odd-pkg"
cat > "$src/good-pkg/recipe.sh" <<'RECIPE'
#!/bin/sh
pkgname=good-pkg
pkgver=1.0
pkgrel=2
pkgdesc='A good package'
license='MIT'
origin=good-pkg
repo=main
url=https://example.invalid/good
source=https://example.invalid/good-pkg-${pkgver}.tar.gz
sha256=aaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999
depends=""
makedepends="gcc make"
subpackages="$pkgname-dev"
recipe_build() { :; }
recipe_install() { :; }
RECIPE
printf 'fake-archive-bytes' > "$src/good-pkg/files/good-pkg-1.0.tar.gz"
printf 'x  good-pkg-1.0.tar.gz\n' > "$src/good-pkg/files/good-pkg-1.0.tar.gz.sha256"
printf 'upstream signature\n' > "$src/good-pkg/files/good-pkg-1.0.tar.gz.asc"
printf '%s\n' '--- fix' > "$src/good-pkg/files/fix.patch"
cat > "$src/withheld-pkg/recipe.sh" <<'RECIPE'
#!/bin/sh
pkgname=withheld-pkg
pkgver=9.9
pkgrel=1
pkgdesc='Held-back package'
license='Proprietary'
origin=withheld-pkg
repo=saphira
url=https://internal.invalid/withheld-pkg
source=https://internal.invalid/withheld-pkg-9.9.tar.gz
sha256=ffffeeeeddddccccbbbbaaaa9999888877776666555544443333222211110000
depends="good-pkg"
makedepends="gcc make"
recipe_build() { :; }
recipe_install() { :; }
RECIPE
printf 'heldback-bytes' > "$src/withheld-pkg/files/withheld-pkg-9.9.tar.gz"
printf 'x  withheld-pkg-9.9.tar.gz\n' > "$src/withheld-pkg/files/withheld-pkg-9.9.tar.gz.sha256"
cat > "$src/odd-pkg/recipe.sh" <<'RECIPE'
#!/bin/sh
pkgname=odd-pkg
pkgver=2.1
pkgrel=1
pkgdesc='Ahead of repo'
license='MIT'
origin=odd-pkg
repo=main
url=https://example.invalid/odd
depends=""
makedepends="gcc make"
recipe_build() { :; }
recipe_install() { :; }
RECIPE
printf 'top docs\n' > "$src/README.md"
git -C "$src" init -q -b Master
git -C "$src" -c user.name=t -c user.email=t@t add -A
git -C "$src" -c user.name=t -c user.email=t commit -qm fixture

live=$test_root/live
mkdir -p "$live"
: > "$live/good-pkg-1.0-r2.apk"
: > "$live/odd-pkg-2.0-r1.apk"

mkclone()
{
	rm -rf "$test_root/pub"
	mkdir -p "$test_root/pub"
	git -C "$test_root/pub" init -q -b Master
	printf 'community\n' > "$test_root/pub/COMMUNITY.md"
	git -C "$test_root/pub" -c user.name=t -c user.email=t add -A
	git -C "$test_root/pub" -c user.name=t -c user.email=t commit -qm seed
}

# --- baseline: without exclusion the withheld tree exports (the --------
# --- exclusion list is the control, not magic) -----------------------------
mkclone
"$sync" "$src" "$test_root/pub" --live-repo "$live" > "$test_root/base.out" 2>&1
test -d "$test_root/pub/withheld-pkg"
test -f "$test_root/pub/withheld-pkg/files/withheld-pkg-9.9.tar.gz.sha256"
python3 - "$test_root/pub/recipes.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    names = {item["name"] for item in json.load(stream)["packages"]}
assert "withheld-pkg" in names, sorted(names)
print("baseline: OK")
PY

# --- clean export with exclusion -------------------------------------------
mkclone
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg --message "test sync" > "$test_root/sync.out" 2>&1
test ! -e "$test_root/pub/withheld-pkg"
test ! -e "$test_root/pub/good-pkg/files/good-pkg-1.0.tar.gz"
test -f "$test_root/pub/good-pkg/files/good-pkg-1.0.tar.gz.sha256"
test -f "$test_root/pub/good-pkg/files/good-pkg-1.0.tar.gz.asc"
test -f "$test_root/pub/good-pkg/files/fix.patch"
test -f "$test_root/pub/good-pkg/recipe.sh"
test -f "$test_root/pub/COMMUNITY.md"
test -f "$test_root/pub/recipes.json"
test -f "$test_root/pub/README.md"
# excluded name appears nowhere (case-insensitive whole tree)
if grep -rli 'withheld-pkg' "$test_root/pub" --exclude-dir=.git; then
	printf '%s\n' 'excluded name leaked into export' >&2
	exit 1
fi
python3 - "$test_root/pub/recipes.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    index = json.load(stream)
assert set(index) == {"generated", "source_tree", "repository",
                      "arch", "recipe_count", "hatched_main_packages",
                      "packages"}, sorted(index)
by_name = {item["name"]: item for item in index["packages"]}
assert set(by_name) == {"good-pkg", "odd-pkg"}, sorted(by_name)
good = by_name["good-pkg"]
assert good["recipe_version"] == "1.0", good
assert good["recipe_revision"] == 2, good
assert good["license"] == "MIT", good
assert good["source"] == "https://example.invalid/good-pkg-1.0.tar.gz", good
assert good["in_hatched"] is True, good
assert good["hatched_nvr"] == "good-pkg-1.0-r2", good
assert good["recipe_ahead_of_hatched"] is False, good
odd = by_name["odd-pkg"]
assert odd["in_hatched"] is True, odd
assert odd["hatched_nvr"] == "odd-pkg-2.0-r1", odd
assert odd["recipe_ahead_of_hatched"] is True, odd
assert index["recipe_count"] == 2, index["recipe_count"]
print("index: OK")
PY
git -C "$test_root/pub" log --oneline | grep -q 'test sync'

# --- a committed past leak in public history must FAIL the gate -----------
mkdir -p "$test_root/pub/stalevil"
printf 'withheld-pkg was here\n' > "$test_root/pub/stalevil/note.txt"
git -C "$test_root/pub" -c user.name=t -c user.email=t add -A
git -C "$test_root/pub" -c user.name=t -c user.email=t commit -qm 'past leak'
if "$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/stale.out" 2> "$test_root/stale.err"; then
	printf '%s\n' 'stale leak unexpectedly passed' >&2
	exit 1
fi
grep -i 'leak' "$test_root/stale.err" >/dev/null
# The leak persists in public history by design (fail-closed every
# time); subsequent tests need a fresh clone.
mkclone
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg --message "test sync" >/dev/null 2>&1

# --- idempotent re-run: nothing to commit ----------------------------------

# --- idempotent re-run: nothing to commit ----------------------------------
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/rerun.out" 2>&1
grep -q 'no changes' "$test_root/rerun.out"

# --- dirty public clone is refused -----------------------------------------
printf 'dirty\n' >> "$test_root/pub/COMMUNITY.md"
if "$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/dirty.out" 2> "$test_root/dirty.err"; then
	printf '%s\n' 'dirty clone unexpectedly accepted' >&2
	exit 1
fi
grep -q 'uncommitted state' "$test_root/dirty.err"

# --- regression: disguised archives, payload excludes, private refs --------
# --- stale excluded payload must FAIL, .git must survive --------------------
# Fresh clone + source additions that mirror the real 12-finding outage:
# gzip tag snapshots with no extension (iniparser v4.3.2 / ndctl v85 style),
# gzip "master" snapshots (pppd/rp-pppoe style), DER cert (regdb.x509 style),
# latin-1 usb.ids style, and keeper-colon/git-at private refs.
mkclone
src_disc=$src/disc-pkg
mkdir -p "$src_disc/files"
# gzip with no extension (tag snapshot) + its .sha256 sidecar (must ship)
python3 -c "import gzip; gzip.open('$src_disc/files/v4.3.2','wb').write(b'disguised-archive-bytes')"
printf 'x  v4.3.2\n' > "$src_disc/files/v4.3.2.sha256"
python3 -c "import gzip; gzip.open('$src_disc/files/master','wb').write(b'disguised-master-bytes')"
printf 'x  master\n' > "$src_disc/files/master.sha256"
# DER-style cert bytes (not gzip/ELF, so only the payload-exclude bars it)
printf 'fake-cert-bytes-not-archive' > "$src_disc/files/saphira-regdb.x509"
printf 'x  saphira-regdb.x509\n' > "$src_disc/files/saphira-regdb.x509.sha256"
# latin-1 usb.ids style (0xb4 fails strict UTF-8; gate must flag via payload exclude)
python3 -c "open('$src_disc/files/usb.ids','wb').write(b'# usb\n\xb4latin1\n')"
printf 'x  usb.ids\n' > "$src_disc/files/usb.ids.sha256"
cat > "$src_disc/recipe.sh" <<'RECIPE'
#!/bin/sh
pkgname=disc-pkg
pkgver=1.0
pkgrel=1
pkgdesc='Disguised payload fixture'
license='MIT'
origin=disc-pkg
repo=main
url=https://example.invalid/disc
depends=""
makedepends=""
recipe_build() { :; }
recipe_install() { :; }
RECIPE
git -C "$src" -c user.name=t -c user.email=t@t add -A
git -C "$src" -c user.name=t -c user.email=t commit -qm 'disguised payload fixture'
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg --message "disc sync" > "$test_root/disc.out" 2>&1
# Archives + payload excludes must be absent; sidecars + recipe must ship.
test ! -e "$test_root/pub/disc-pkg/files/v4.3.2"
test ! -e "$test_root/pub/disc-pkg/files/master"
test ! -e "$test_root/pub/disc-pkg/files/saphira-regdb.x509"
test ! -e "$test_root/pub/disc-pkg/files/usb.ids"
test -f "$test_root/pub/disc-pkg/files/v4.3.2.sha256"
test -f "$test_root/pub/disc-pkg/files/master.sha256"
test -f "$test_root/pub/disc-pkg/recipe.sh"
# .git survives the clear + export cycle.
test -d "$test_root/pub/.git"
test -f "$test_root/pub/.git/HEAD"
# A keeper-colon/git-at string inside .git must NOT fail the gate (pruned).
K=keeper; K="$K:"; printf "%s should-be-ignored-in-git\n" "$K" > "$test_root/pub/.git/keeper-should-be-ignored"
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/gitprune.out" 2>&1
grep -q 'no changes' "$test_root/gitprune.out"
rm -f "$test_root/pub/.git/keeper-should-be-ignored"
# Stale excluded payload committed in public history must FAIL loudly.
# Public-only top dir (no source counterpart) is preserved via snapshot,
# exactly how rsync --exclude without --delete-excluded lingered stale
# copies under exclusion cover in the manual tool.
mkdir -p "$test_root/pub/stale-payload/files"
printf 'stale-cert\n' > "$test_root/pub/stale-payload/files/saphira-regdb.x509"
printf 'stale-usb\n' > "$test_root/pub/stale-payload/files/usb.ids"
python3 -c "import gzip; gzip.open('$test_root/pub/stale-payload/files/v4.3.2','wb').write(b'stale-archive')"
git -C "$test_root/pub" -c user.name=t -c user.email=t add -A
git -C "$test_root/pub" -c user.name=t -c user.email=t commit -qm 'stale payload leak'
if "$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/stalepayload.out" 2> "$test_root/stalepayload.err"; then
	printf '%s\n' 'stale payload unexpectedly passed' >&2
	exit 1
fi
grep -q 'excluded payload present' "$test_root/stalepayload.err"
grep -q 'archive present (magic)' "$test_root/stalepayload.err"
mkclone
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg --message "disc sync" >/dev/null 2>&1
# Private-location patterns fail closed (keeper-colon + git-at), with the single
# shampoo exception accepted loudly.
mkdir -p "$test_root/pub/stalepriv"
K=keeper; K="$K:"; printf 'mirror %s/internal/repo.git at abc\n' "$K" > "$test_root/pub/stalepriv/note.txt"
git -C "$test_root/pub" -c user.name=t -c user.email=t add -A
git -C "$test_root/pub" -c user.name=t -c user.email=t commit -qm 'private leak'
if "$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/priv.out" 2> "$test_root/priv.err"; then
	printf '%s\n' 'private pattern unexpectedly passed' >&2
	exit 1
fi
K=keeper; K="$K:"; grep -q "private pattern '$K'" "$test_root/priv.err"
mkclone
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg --message "disc sync" >/dev/null 2>&1
# git-at SSH form fails except for the accepted shampoo exception.
G=git; G="$G@"; printf 'gitsource="%sgithub.com:example/private.git"\n' "$G" > "$test_root/pub/stalepriv2.txt"
git -C "$test_root/pub" -c user.name=t -c user.email=t add -A
git -C "$test_root/pub" -c user.name=t -c user.email=t commit -qm 'ssh leak'
if "$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/ssh.out" 2> "$test_root/ssh.err"; then
	printf '%s\n' 'ssh pattern unexpectedly passed' >&2
	exit 1
fi
G=git; G="$G@"; grep -q "private pattern '$G'" "$test_root/ssh.err"
# Accepted exception does not fail (public-only location, kept via snapshot).
mkclone
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg --message "disc sync" >/dev/null 2>&1
mkdir -p "$test_root/pub/staleallowed"
G=git; G="$G@"; printf 'gitsource="%sgithub.com:SaphiraLinux/shampoo.git"\n' "$G" > "$test_root/pub/staleallowed/allowed.txt"
git -C "$test_root/pub" -c user.name=t -c user.email=t add -A
git -C "$test_root/pub" -c user.name=t -c user.email=t commit -qm 'allowed exception'
"$sync" "$src" "$test_root/pub" --live-repo "$live" \
	--exclude-recipe withheld-pkg > "$test_root/allowed.out" 2>&1
grep -q 'accepted exception' "$test_root/allowed.out"

printf '%s\n' 'sync-public-mirror export, exclusion, and leakage-gate tests: OK'

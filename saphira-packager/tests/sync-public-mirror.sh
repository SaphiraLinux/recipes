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

printf '%s\n' 'sync-public-mirror export, exclusion, and leakage-gate tests: OK'

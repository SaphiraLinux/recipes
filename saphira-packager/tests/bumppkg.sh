#!/bin/bash
# bumppkg suite: guards, ledger, all/set-all-max - entirely on fixtures.
# The real /recipes tree is never touched: every run uses SAPHIRA_*
# overrides inside a mktemp directory.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BUMPPKG=${1:?usage: bumppkg.sh PATH-TO-bumppkg}

pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1" >&2; }
assert_contains() { grep -qF -- "$2" "$1" && ok || bad "$3 (missing: $2)"; }
assert_not_contains() { grep -qF -- "$2" "$1" && bad "$3 (unexpected: $2)" || ok; }
assert_line() { grep -qF -- "$2" "$1" && ok || bad "$3"; }
assert_eq() { [ "$2" = "$3" ] && ok || bad "$1 (got: $2, want: $3)"; }

TMP=$(mktemp -d /tmp/saphira-bumppkg-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/recipes" "$TMP/repo" "$TMP/state"

mkrecipe() {
	mkdir -p "$TMP/recipes/$1"
	cat > "$TMP/recipes/$1/recipe.sh" <<EOF
#!/bin/sh
pkgname=$1
pkgver=$2
pkgrel=$3
pkgarch=\${SAPHIRA_ARCH:-x86_64}
pkgdesc='fixture'
license=MIT
origin=$1
repo=saphira
url=https://saphira.vm2.uk/
recipe_build() { :; }
recipe_install() { :; }
EOF
}
mkrecipe goodpkg 1.0 1
mkrecipe pkg2     1.0 0
mkrecipe newpkg   2.0 0
mkrecipe maxpkg   3.0 15
mkdir -p "$TMP/recipes/dispkg"
cat > "$TMP/recipes/dispkg/recipe.sh" <<'EOF'
#!/bin/sh
pkgname=dispkg
pkgver=1.0
pkgrel=9
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='fixture'
license=MIT
origin=dispkg
repo=saphira
url=https://saphira.vm2.uk/
disabled=yes
disabled_reason='fixture disabled'
recipe_build() { :; }
recipe_install() { :; }
EOF
: > "$TMP/repo/goodpkg-1.0-r1.apk"
: > "$TMP/repo/pkg2-1.0-r0.apk"

env()
{
	SAPHIRA_RECIPES="$TMP/recipes" SAPHIRA_RELEASE_STATE="$TMP/state" \
		SAPHIRA_REPO="$TMP/repo" BUMPPKG_ASSUME_YES=1 \
		python3 "$BUMPPKG" "$@"
}

rel_of() { grep -m1 '^pkgrel=' "$TMP/recipes/$1/recipe.sh" | cut -d= -f2; }

out=$TMP/out.txt

# --- status -----------------------------------------------------------
env status > "$out" 2>&1
assert_contains "$out" "goodpkg" "status lists goodpkg"
assert_contains "$out" "r1" "status shows published rel"
assert_contains "$out" "[DISABLED]" "status marks disabled"

# --- never-published guard --------------------------------------------
env bump newpkg > "$out" 2>&1 && bad "unpublished bump should fail" || ok "unpublished bump refused"
assert_contains "$out" "never published" "refusal explains churn reason"
assert_eq "newpkg pkgrel unchanged" "$(rel_of newpkg)" "0"

# --- single bump + ledger ---------------------------------------------
env bump goodpkg > "$out" 2>&1 || bad "goodpkg bump failed"
assert_eq "goodpkg r1 -> r2" "$(rel_of goodpkg)" "2"
assert_contains "$out" "1 package(s) bumped" "bump reports count"
[ -s "$TMP/state/releases.jsonl" ] && ok "ledger written" || bad "ledger missing"
assert_contains "$TMP/state/releases.jsonl" '"action": "bump"' "ledger action"

# --- anti-loop guard --------------------------------------------------
env bump goodpkg > "$out" 2>&1 && bad "re-bump within 24h should fail" || ok "anti-loop refused"
assert_contains "$out" "anti-loop" "anti-loop explains itself"
assert_eq "goodpkg still r2" "$(rel_of goodpkg)" "2"

# --- --force bypass ---------------------------------------------------
env bump --force goodpkg > "$out" 2>&1 || bad "forced bump failed"
assert_eq "goodpkg forced to r3" "$(rel_of goodpkg)" "3"

# --- all (world bump) -------------------------------------------------
env all > "$out" 2>&1 || bad "all failed"
assert_contains "$out" "FULL WORLD REBUILD" "all warns about world rebuild"
assert_contains "$out" "skip: newpkg" "all skips never-published"
assert_contains "$out" "skip: maxpkg" "all skips never-published maxpkg"
assert_contains "$out" "skip: dispkg" "all skips disabled"
assert_eq "pkg2 (r0-published) bumped to r1" "$(rel_of pkg2)" "1"
assert_eq "goodpkg not double-bumped" "$(rel_of goodpkg)" "3"
env all > "$out" 2>&1 && bad "second all within 24h should fail" || ok "world anti-loop refused"
assert_contains "$out" "anti-loop guard" "world anti-loop explains itself"

# --- set all max ------------------------------------------------------
env set all max > "$out" 2>&1 && bad "set all max within 24h of world bump should fail" || ok "set-all-max anti-loop refused"
rm -f "$TMP/state/releases.jsonl"
env set all max > "$out" 2>&1 || bad "set all max failed"
assert_contains "$out" "global maximum is r15" "set-all-max computes max"
assert_eq "goodpkg aligned to r16" "$(rel_of goodpkg)" "16"
assert_eq "pkg2 aligned to r16" "$(rel_of pkg2)" "16"
assert_eq "newpkg aligned to r16" "$(rel_of newpkg)" "16"
assert_eq "maxpkg aligned to r16" "$(rel_of maxpkg)" "16"
assert_eq "dispkg untouched" "$(rel_of dispkg)" "9"

# --- history ----------------------------------------------------------
env history > "$out" 2>&1
assert_contains "$out" "all-max" "history shows all-max entries"

echo "bumppkg suite: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

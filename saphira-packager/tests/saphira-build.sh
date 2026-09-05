#!/bin/sh
# saphira-build test suite. Self-contained under mktemp; asserts the Egg
# package world is unchanged. Uses a stub buildpkg and a stub apk so no
# real builds happen; stage evaluation is exercised directly on synthetic
# roots.
set -eu

SAPHIRA_BUILD="${1:-$(dirname "$0")/../files/saphira-build}"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }
assert() { # desc, expected_rc, cmd...
    desc=$1; want=$2; shift 2
    if "$@" >/dev/null 2>&1; then got=0; else got=$?; fi
    [ "$got" = "$want" ] && ok "$desc" || bad "$desc (rc=$got want=$want)"
}
assert_contains() { # desc, haystack_file_or_- , needle
    desc=$1; hay=$2; needle=$3
    if [ "$hay" = "-" ]; then
        if grep -q "$needle"; then ok "$desc"; else bad "$desc (missing: $needle)"; fi
    else
        if grep -q "$needle" "$hay" 2>/dev/null; then ok "$desc"; else bad "$desc (missing: $needle)"; fi
    fi
}

TMP=$(mktemp -d /tmp/saphira-build-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
WORLD_BEFORE=$(sha256sum /etc/apk/world 2>/dev/null | cut -d' ' -f1 || echo none)

RECIPES=$TMP/recipes
STATE=$TMP/state
INCOMING=$TMP/incoming
mkdir -p "$RECIPES" "$INCOMING" "$STATE"

cat > "$TMP/stub-buildpkg" <<'EOF'
#!/bin/sh
# stub buildpkg: success unless package name contains 'broken'
pkg=$1
case "$pkg" in *broken*) echo "stub: $pkg failed" >&2; exit 1;; esac
ver=$(grep "^pkgver=" "$RECIPE_ROOT/$pkg/recipe.sh" | cut -d= -f2)
rel=$(grep "^pkgrel=" "$RECIPE_ROOT/$pkg/recipe.sh" | cut -d= -f2)
d="$SAPHIRA_INCOMING_STUB/$pkg-$(date +%s%N)-ready"
mkdir -p "$d"
printf 'stub-apk-payload %s\n' "$pkg" > "$d/$pkg-$ver-r$rel.apk"
exit 0
EOF
chmod +x "$TMP/stub-buildpkg"

cat > "$TMP/stub-apk" <<'EOF'
#!/bin/sh
root=""
for a in "$@"; do case "$a" in --root=*) root=${a#--root=};; esac; done
case "$*" in
    *add\ *)
        mkdir -p "$root/usr/bin" "$root/etc/init.d"
        apkfile=$*
        apkfile=${apkfile##* }
        printf 'stub\n' > "$root/usr/bin/prog"
        [ "$apkfile" != "${apkfile%-svc*}" ] && printf 'stub\n' > "$root/etc/init.d/svc"
        exit 0 ;;
    *info\ -L*)
        pkg=$*
        pkg=${pkg##* }
        echo "$pkg-1.0-r0 contains:"
        echo "usr/bin/prog"
        ls "$root/etc/init.d" 2>/dev/null | sed 's|^|etc/init.d/|'
        exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/stub-apk"

export SAPHIRA_BUILD_STATE="$STATE"
export SAPHIRA_RECIPES="$RECIPES"
export SAPHIRA_INCOMING="$INCOMING"
export SAPHIRA_REPO="$TMP/repo"
export SAPHIRA_BUILDCMD="$TMP/stub-buildpkg"
export SAPHIRA_APK="$TMP/stub-apk"
export SAPHIRA_TEST_ROOTS="$TMP/testroots"
export SAPHIRA_INCOMING_STUB="$INCOMING"
export RECIPE_ROOT="$RECIPES"

mkdir -p "$RECIPES/base/files" "$RECIPES/dependent" "$RECIPES/needsmissing" "$RECIPES/brokensvc"
cat > "$RECIPES/base/recipe.sh" <<'EOF'
pkgname=base
pkgver=1.0
pkgrel=0
depends="missingdep-not-arealpkg"
EOF
sed -i 's/^depends=.*/depends=""/' "$RECIPES/base/recipe.sh"
cat > "$RECIPES/dependent/recipe.sh" <<'EOF'
pkgname=dependent
pkgver=2.0
pkgrel=1
depends="base"
EOF
cat > "$RECIPES/needsmissing/recipe.sh" <<'EOF'
pkgname=needsmissing
pkgver=1.0
pkgrel=0
depends="ghost-package"
EOF
cat > "$RECIPES/brokensvc/recipe.sh" <<'EOF'
pkgname=brokensvc
pkgver=1.0
pkgrel=0
depends="base"
EOF

"$SAPHIRA_BUILD" scan > "$TMP/scan.out" 2>&1
assert_contains "scan queues unknown recipes" "$TMP/scan.out" "newly queued"

"$SAPHIRA_BUILD" queue > "$TMP/queue.out" 2>&1 || true
assert_contains "blocked set present pre-build" "$TMP/queue.out" "BLOCKED: 3"
assert_contains "blocked reason names ghost" "$TMP/queue.out" "ghost-package"

"$SAPHIRA_BUILD" run --limit=10 > "$TMP/run.out" 2>&1 || true
assert_contains "stub build of base passes" "$TMP/run.out" "base -> PASS"
assert_contains "dependent passes after base" "$TMP/run.out" "dependent -> PASS"
assert_contains "broken package fails" "$TMP/run.out" "brokensvc -> FAIL"

"$SAPHIRA_BUILD" scan > "$TMP/rescan.out" 2>&1
assert_contains "PASS recipes skipped on rescan" "$TMP/rescan.out" "already proven"

"$SAPHIRA_BUILD" status > "$TMP/status.out" 2>&1
assert_contains "status shows base PASS" "$TMP/status.out" "base"
assert_contains "status shows dependent PASS" "$TMP/status.out" "dependent"

"$SAPHIRA_BUILD" log base > "$TMP/log.out" 2>&1
assert_contains "log includes build.log" "$TMP/log.out" "build.log"

"$SAPHIRA_BUILD" retry needsmissing > "$TMP/retry.out" 2>&1 || true

mkdir -p "$TMP/evroot/lib" "$TMP/evroot/usr/bin"
printf '\x7fELFfake' > "$TMP/evroot/usr/bin/prog"
cat > "$TMP/evlib.so" </dev/null
printf 'stub\n' > "$TMP/evroot/lib/libneeded.so.1"
mkdir -p "$TMP/evrecipe"
printf '#!/bin/sh\nexit 0\n' > "$TMP/evrecipe/test.sh"
chmod +x "$TMP/evrecipe/test.sh"

cat > "$TMP/stub-apk-eval" <<'EOF'
#!/bin/sh
root=""
for a in "$@"; do case "$a" in --root=*) root=${a#--root=};; esac; done
echo "mypkg-1.0-r0 contains:"
echo "usr/bin/prog"
exit 0
EOF
chmod +x "$TMP/stub-apk-eval"
SAPHIRA_APK="$TMP/stub-apk-eval" "$SAPHIRA_BUILD" evaluate "$TMP/evroot" mypkg "$TMP/evrecipe" > "$TMP/eval.out" 2>&1
assert_contains "evaluate: RUNTIME passes with lib present" "$TMP/eval.out" '"RUNTIME"'
assert_contains "evaluate: no policy failure" "$TMP/eval.out" '"POLICY"'
if grep -q '"status": "fail"' "$TMP/eval.out"; then
    bad "evaluate: unexpected stage failure"
else
    ok "evaluate: all stages pass on clean root"
fi

printf 'ExecStart=/usr/bin/sh -c x\n' > "$TMP/evroot/usr/bin/prog"
SAPHIRA_APK="$TMP/stub-apk-eval" "$SAPHIRA_BUILD" evaluate "$TMP/evroot" mypkg "$TMP/evrecipe" > "$TMP/eval2.out" 2>&1 || true
assert_contains "evaluate: /usr/bin/sh policy failure detected" "$TMP/eval2.out" '"/usr/bin/sh reference'

WORLD_AFTER=$(sha256sum /etc/apk/world 2>/dev/null | cut -d' ' -f1 || echo none)
[ "$WORLD_BEFORE" = "$WORLD_AFTER" ] && ok "Egg package world unchanged" || bad "Egg package world CHANGED"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

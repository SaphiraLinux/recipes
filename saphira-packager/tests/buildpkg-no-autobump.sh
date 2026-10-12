#!/bin/sh

# buildpkg: no automatic pkgrel bump, and honest failure reporting.
#
# Two defects, one root cause: buildpkg used to act on its own initiative in
# ways that hid the real story from whoever has to act next.
#
# 1. AUTO-BUMP. When a built payload differed from the published artifact,
#    buildpkg rewrote the recipe's pkgrel, appended a ledger entry, and died
#    demanding a rebuild:
#
#      recipe.write_text(re.sub(r"^pkgrel=\d+\s*$", f"pkgrel={new_rel}", ...))
#      die(f"payload differs from published {package.name}: recipe auto-bumped
#           r{old_rel} -> r{new_rel} ...; rebuild required")
#
#    That is a build tool silently editing a version-controlled recipe. It
#    invents an NVR nobody reviewed, leaves the tree dirty with no commit, and
#    it cannot converge: the recipe is bumped once per run and the run then
#    dies, so a package requeued in a loop burns a full rebuild per cycle and
#    only trips REQUEUE_WARN_THRESHOLD, which merely prints. The pkgrel bump is
#    a decision that needs the diff in front of a human, so buildpkg now
#    refuses and says what to run instead.
#
# 2. FAILURE MASKING. Every build runs through the nsenter/bwrap wrapper, and
#    the failure path reported the wrapper's own argv[0]:
#
#      die(f"command failed ({exc.returncode}): {command[0]}")
#
#    so every possible build error printed the identical, useless line
#
#      buildpkg: command failed (2): /usr/bin/nsenter
#
#    This is not cosmetic. A missing build dependency surfaced only as that
#    line in the builder daemon's log; the actual cause (lshw:
#    "msgfmt: No such file or directory") was findable only by opening the
#    retained workspace log by hand. The stage is now named, and the message
#    points at the log holding the detail.
#
# The contract: buildpkg never writes to a recipe, and every failure names the
# stage that failed instead of the wrapper it happens to run through.

set -u

BUILDPKG=${1:-"$(dirname "$0")/../files/buildpkg"}
[ -f "$BUILDPKG" ] || BUILDPKG=/usr/lib/saphira-packager/buildpkg
[ -f "$BUILDPKG" ] || { echo "buildpkg not found" >&2; exit 2; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want '$1', got '$2')"; fi; }

echo "buildpkg auto-bump removal and failure-reporting contract"
echo "  buildpkg: $BUILDPKG"

# --- 1. buildpkg must not write to a recipe ---------------------------------
if grep -q 'recipe\.write_text' "$BUILDPKG"; then
	no "buildpkg never rewrites a recipe (found recipe.write_text)"
else
	ok "buildpkg never rewrites a recipe"
fi
if grep -q 'recipe\.write_text' "$BUILDPKG"; then
	no "no pkgrel is written back into recipe.sh"
else
	ok "no pkgrel is written back into recipe.sh"
fi

# --- 2. the auto-bump machinery is gone, not merely renamed -------------------
for token in 'auto-bump-payload-change' 'auto-bumped' 'RELEASE_STATE'; do
	if grep -q "$token" "$BUILDPKG"; then
		no "auto-bump token removed: $token"
	else
		ok "auto-bump token removed: $token"
	fi
done

# --- 3. the refusal explains itself and names the fix ------------------------
if grep -q 'payload differs from published' "$BUILDPKG"; then
	ok "payload-differs is still detected (guard not deleted)"
else
	no "payload-differs is still detected (guard not deleted)"
fi
if grep -q 'bumppkg {self.target}' "$BUILDPKG"; then
	ok "refusal names the bumppkg command to run"
else
	no "refusal names the bumppkg command to run"
fi
if grep -q 'Refusing rather than bumping' "$BUILDPKG"; then
	ok "refusal states that no automatic bump happens"
else
	no "refusal states that no automatic bump happens"
fi

# --- 4. run() names the stage, not the wrapper -------------------------------
if grep -q 'def run(self, command' "$BUILDPKG" && grep -q 'label: str = ""' "$BUILDPKG"; then
	ok "run() accepts a stage label"
else
	no "run() accepts a stage label"
fi
if grep -q 'stage failed (rc=' "$BUILDPKG"; then
	ok "failure message names the stage and rc"
else
	no "failure message names the stage and rc"
fi
# The old defect verbatim: reporting command[0] is the wrapper for every build.
if grep -q 'die(f"command failed ({exc.returncode}): {command\[0\]}")' "$BUILDPKG"; then
	no "failure no longer reports the wrapper argv[0]"
else
	ok "failure no longer reports the wrapper argv[0]"
fi
if grep -q 'logs" / "buildpkg.log' "$BUILDPKG"; then
	ok "failure points at the workspace build log"
else
	no "failure points at the workspace build log"
fi

# --- 5. every call site is labelled (AST, not grep) --------------------------
sites=$(python3 - "$BUILDPKG" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
total = labelled = 0
missing = []
for node in ast.walk(tree):
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "run"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "self"):
        total += 1
        if "label" in {k.arg for k in node.keywords}:
            labelled += 1
        else:
            missing.append(node.lineno)
print(f"{labelled} {total} {','.join(str(m) for m in missing) or 'none'}")
PY
)
set -- $sites
check "$2" "$1" "every self.run() call site carries a label"
[ "$3" = "none" ] && ok "no unlabelled call site remains" \
	|| no "unlabelled self.run() at line(s): $3"

# --- 6. mutation: the suite must fail if the defect returns ------------------
# Proved rather than asserted. Re-introduce the exact old line and confirm the
# guard above notices; a test that cannot fail is not a test.
if command -v python3 >/dev/null 2>&1; then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	python3 - "$BUILDPKG" "$tmp/mutant.py" <<'PY'
import sys
src = open(sys.argv[1]).read()
# reinstate precisely the removed behaviour
old = 'die(\n                f"payload differs from published {package.name}: the recipe changed "'
new = ('recipe.write_text(text, encoding="utf-8")\n            '
       'die(\n                f"payload differs from published {package.name}: the recipe changed "')
assert old in src, "anchor for mutation not found"
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
	if grep -q 'recipe\.write_text' "$tmp/mutant.py"; then
		ok "mutation reintroduces recipe.write_text (guard is load-bearing)"
	else
		no "mutation did not reintroduce the defect (test is vacuous)"
	fi
	# and the labelled-call-site check must notice an unlabelled site
	python3 - "$BUILDPKG" "$tmp/mutant2.py" <<'PY'
import sys
src = open(sys.argv[1]).read()
old = 'self.run(command, label="build")'
assert old in src, "anchor for mutation not found"
open(sys.argv[2], "w").write(src.replace(old, 'self.run(command)', 1))
PY
	res=$(python3 - "$tmp/mutant2.py" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
total = labelled = 0
for node in ast.walk(tree):
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "run"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "self"):
        total += 1
        labelled += "label" in {k.arg for k in node.keywords}
print(f"{labelled} {total}")
PY
)
	set -- $res
	[ "$1" != "$2" ] && ok "mutation drops a label and the AST check notices" \
		|| no "mutation was not detected (AST check is vacuous)"
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "buildpkg no-autobump: OK"

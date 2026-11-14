#!/bin/sh
# libc-test recipe checks: vendored sources verify, pins match the
# recipe, Saphira tests are present, and no suite execution happens
# at install time (recipe_install ships the runner and musl-check only).

set -eu

root=$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)
files=$root/files

fail=0
check() {
	if [ "$1" = 0 ]; then
		printf '  ok   %s\n' "$2"
	else
		printf '  FAIL %s\n' "$2"
		fail=1
	fi
}

# 1. vendored tarball verifies against its sidecar
(cd "$files" && sha256sum -c libc-test-*.tar.gz.sha256 >/dev/null 2>&1)
check $? "vendored tarball verifies"

# 2. recipe pin matches the sidecar
pin=$(grep -oE 'libc_test_sha256=[0-9a-f]{64}' "$root/recipe.sh" | cut -d= -f2)
side=$(cut -d' ' -f1 "$files"/libc-test-*.tar.gz.sha256)
[ "$pin" = "$side" ]
check $? "recipe pin matches sidecar"

# 3. Saphira tests present and self-contained
n=$(ls "$files"/saphira/*.c 2>/dev/null | wc -l)
[ "$n" -ge 1 ]
check $? "saphira tests present ($n)"

# 4. runner is executable shell, no install-time execution hook
[ -x "$files/libc-test-run" ] && head -1 "$files/libc-test-run" | grep -q '^#!/bin/sh'
check $? "runner executable"
! grep -q "recipe_install.*libc-test-run\|libc-test-run.*install" "$root/recipe.sh"
check $? "recipe_install never executes the suite"

# 5. baseline exists and is valid JSON
python3 -c "import json; json.load(open('$files/baseline.json'))" 2>/dev/null
check $? "baseline.json valid"
python3 - "$files/baseline.json" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
bad = [k for k in d if k.startswith('math/') and k.endswith(':static') and d[k]['expected'] == 'SKIP']
sys.exit(1 if bad else 0)
PY
check $? "baseline covers static math (no SKIP)"

# 6. recipe has no network fetch at build time
! grep -qE "git clone|git fetch|git pull|curl |wget " "$root/recipe.sh"
check $? "no network fetch in recipe"

# 7. musl static/dynamic check ships with the package
[ -x "$files/libc-test-musl-check" ] && head -1 "$files/libc-test-musl-check" | grep -q '^#!/bin/sh'
check $? "musl-check executable"
grep -q 'musl-static' "$root/recipe.sh"
check $? "recipe depends on musl-static"
grep -q 'saphira/\*.mk' "$root/recipe.sh"
check $? "saphira build copies test makefiles"

# 8. two-tree linkage build with the musl-static toolchain
grep -q 'SRC_STATIC=' "$root/recipe.sh"
check $? "recipe builds a dedicated static tree"
grep -A6 '^makedepends=' "$root/recipe.sh" | grep -q 'musl-static'
check $? "musl-static in makedepends"
grep -q 'musl-static-gcc' "$root/recipe.sh"
check $? "static toolchain wired"

# 9. runner honesty: human-first report, JSONL to file only, trustworthy verdicts
grep -q 'Saphira libc-test' "$files/libc-test-run" && grep -q 'Dynamic musl' "$files/libc-test-run" && grep -q 'Static musl' "$files/libc-test-run"
check $? "runner prints the human-readable summary sections"
grep -q 'Overall:' "$files/libc-test-run" && grep -q 'Failures:' "$files/libc-test-run" && grep -q 'Coverage:' "$files/libc-test-run"
check $? "runner reports failures, coverage and overall verdict"
! grep -q '/dev/stdout' "$files/libc-test-run"
check $? "no JSONL to the terminal by default"
grep -q 'needs a FILE, not -' "$files/libc-test-run"
check $? "runner refuses --jsonl - (capture integrity)"
grep -q 'overall=INCOMPLETE' "$files/libc-test-run" && grep -q 'overall=FAIL' "$files/libc-test-run" && grep -q 'overall=PASS' "$files/libc-test-run"
check $? "runner distinguishes PASS / FAIL / INCOMPLETE"
! grep -vE '^[[:space:]]*#' "$files/libc-test-run" | grep -qF '$exp:$result)'
check $? "no self-matching verdict pattern (every verdict was ok)"
[ "$(grep -c "<<'PY'" "$files/libc-test-run")" = "$(grep -c '^PY$' "$files/libc-test-run")" ] && [ "$(grep -c "<<'PY'" "$files/libc-test-run")" -ge 1 ]
check $? "heredocs opened and closed in pairs (no code inside the coverage heredoc)"
! grep -vE '^[[:space:]]*#' "$files/libc-test-run" | grep -E '\| *head'
check $? "no head on a live pipe in the runner"

# 10. build lifecycle: enumerated compile-only goals, failures propagate, no test execution
nmk=$(grep -cE '^[[:space:]]*make[[:space:]]' "$root/recipe.sh")
[ "$nmk" = 2 ]
check $? "exactly two make invocations, one per linkage ($nmk)"
grep -qE '^[[:space:]]*make.*\$DYN_EXES' "$root/recipe.sh" && grep -qE '^[[:space:]]*make.*\$STATIC_EXES' "$root/recipe.sh"
check $? "dynamic builds exe+dso only, static builds static-exe only"
! grep -E '^[[:space:]]*make[[:space:]]' "$root/recipe.sh" | grep -qE '(^|[[:space:]])CC='
check $? "no CC on any make command line (make auto-exports it; wrapper would self-exec)"
grep -qF "printf 'CC = %s" "$root/recipe.sh" && grep -qF '$SRC_STATIC/config.mak' "$root/recipe.sh"
check $? "static CC travels in the static tree config.mak"
! grep -vE '^[[:space:]]*#' "$root/recipe.sh" | grep -E '\| *head'
check $? "no head on a live pipe (SIGPIPE rc=141 under errexit+pipefail)"
[ "$nmk" = "$(grep -cE '^[[:space:]]*make.*[|][|] return 1' "$root/recipe.sh")" ]
check $? "every make invocation propagates failure"
! grep -E '^[[:space:]]*make[[:space:]]' "$root/recipe.sh" | grep -qE 'REPORT| check| test| run:'
check $? "no test-executing make targets"
! grep -E '^[[:space:]]*make[[:space:]]' "$root/recipe.sh" | grep -qE '\.err|/all|/run|api/main|runtest'
check $? "no suite-execution or harness targets"
grep -q 'DYN_ONLY=' "$root/recipe.sh" && grep -q 'saphira/saphira_abi' "$root/recipe.sh"
check $? "dynamic-only exceptions preserved (saphira_abi + upstream)"
grep -q 'for d in functional regression math saphira' "$root/recipe.sh"
check $? "four runtime categories enumerated (api excluded)"
grep -qF '^BUILDERROR ' "$root/recipe.sh"
check $? "BUILDERROR surfaced line-anchored, missing binaries fail closed"
grep -q 'src/functional src/regression src/math src/saphira' "$root/recipe.sh"
check $? "install restricted to runtime categories"

exit $fail

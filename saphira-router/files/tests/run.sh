#!/bin/sh
# saphira-router test entry point.
set -e
cd "$(dirname "$0")/.."
R=${TMPDIR:-/tmp}/sr-test.$$
mkdir -p "$R"; trap 'rm -rf "$R"' EXIT

# Always build. make is incremental, so this costs nothing on a clean tree and
# it is the only way the suite can be trusted to test what is in the tree.
#
# It used to build only when build/saphira-router was MISSING, on the theory
# that a developer had already run make. That silently tests stale objects: edit
# a source file, run the suite, get a green result for the previous code. That
# is not hypothetical -- it is how a deliberately reintroduced audit bug passed
# its own regression test here. A green suite certifying the wrong binary is
# worse than a red one.
echo "== building =="
make -s all

CC=${CC:-gcc}
CFLAGS="-std=c11 -O1 -g -D_GNU_SOURCE -Iinclude -I.deps/include"
ARGON=$(ls /usr/lib/libargon2.so.1 2>/dev/null || echo -largon2)
fail=0

# Run a test, take the exit status FROM THE TEST, then indent its output.
#
# Do not pipe a test into sed. A pipeline's status is the LAST command's, so
# `"$t" | sed ... || fail=1` records sed's success and never notices that the
# test failed. Every invocation here was written that way, which is why a
# genuinely failing assertion still printed ALL SUITES PASS and exited 0.
# Status first, format afterwards.
run() {
  _o=$("$@" 2>&1) && _rc=0 || _rc=$?
  printf '%s\n' "$_o" | sed 's/^/  /'
  if [ "$_rc" -ne 0 ]; then
    echo "  --> FAILED (exit $_rc): $*"
    fail=1
  fi
  return 0
}

# As run, but drops lines matching a filter (used to hide log noise).
run_filtered() {
  _f=$1; shift
  _o=$("$@" 2>&1) && _rc=0 || _rc=$?
  printf '%s\n' "$_o" | grep -vE "$_f" | sed 's/^/  /'
  if [ "$_rc" -ne 0 ]; then
    echo "  --> FAILED (exit $_rc): $*"
    fail=1
  fi
  return 0
}

echo "== db: schema materialises =="
$CC $CFLAGS tests/test_db.c build/util.o build/db.o -o "$R/t_db" -lsqlite3
run "$R/t_db"

echo "== auth + rbac =="
$CC $CFLAGS tests/test_auth.c build/util.o build/db.o build/audit.o build/auth.o build/rbac.o \
    -o "$R/t_auth" -lsqlite3 $ARGON -lcrypto
run "$R/t_auth"

echo "== module loader: ABI version, refusal, describe() -> registry =="
$CC $CFLAGS tests/test_module.c build/util.o build/db.o build/audit.o build/module.o build/rbac.o \
    -o "$R/t_mod" -lsqlite3
run "$R/t_mod" build

echo "== audit trail: refusals recorded, provenance honest =="
$CC $CFLAGS tests/test_audit.c build/util.o build/db.o build/audit.o \
    build/auth.o build/rbac.o -o "$R/t_audit" -lsqlite3 $ARGON -lcrypto
run "$R/t_audit"

# Interactive TUI smoke test through a pty. The registry-driven behaviour is
# proven deterministically elsewhere, but the acceptance criterion is an
# operator looking at a terminal, so the real interface is driven and read.
if command -v python3 >/dev/null 2>&1 && [ -x build/saphira-router ]; then
  echo "== interactive TUI (pty) =="
  run python3 tests/tui_pty.py

  # Terminal resize. Reported as "works over SSH until I resize the window",
  # which is the common case: the operator is never at a physical console.
  # term.py gives a real terminal model (pyte plus REP, which pyte lacks and
  # ncurses relies on) so the assertions read the screen an operator sees.
  echo "== TUI terminal resize (SIGWINCH) =="
  if python3 -c "import sys; sys.path.insert(0, 'tests'); import term" 2>/dev/null; then
    run python3 tests/tui_resize.py
  else
    echo "  NOTE term.py/pyte absent -- resize checks run against the raw stream only"
    run python3 tests/tui_resize.py
  fi
else
  echo "== interactive TUI: SKIPPED =="
fi

# The negative path, with mod_badabi.so live in the module directory on the
# test host. It is the standing fixture for a refused module: the loader must
# refuse it and the refusal must be legible to the operator who has to act on
# it, not merely present in a log. Over ssh, because that is where operators are.
if [ -n "${SR_SSH_TEST_HOST:-}" ] || ssh -o BatchMode=yes -o ConnectTimeout=6 \
       "${SR_SSH_TEST_HOST:-hatchling}" true 2>/dev/null; then
  echo "== negative path: refused module, proven from the operator's seat =="
  run python3 tests/tui_negative.py
else
  echo "== negative path: SKIPPED (no ssh test host) =="
fi

# The D2 9 design test: installing a module makes functionality appear and
# removing it makes it disappear, with the interface sources byte-identical
# throughout.
echo "== design test: registry drives the interface, sources never change =="
$CC $CFLAGS tests/test_registry_ui.c build/util.o build/db.o build/audit.o build/module.o \
    build/rbac.o -o "$R/t_ui" -lsqlite3 -ljson-c
run_filtered '^\[' "$R/t_ui" build

# Integration against a real node: the five-state model proven by exercising
# features, not by inferring them. Skipped when the node is unreachable so
# the suite stays runnable offline.
NODE=${SR_TEST_NODE:-172.16.7.100}
if timeout 10 bash -c "exec 3<>/dev/tcp/$NODE/22" 2>/dev/null; then
  echo "== integration: five-state capability model against $NODE =="
  $CC $CFLAGS tests/test_enroll.c build/util.o build/db.o build/audit.o build/enroll.o \
      -o "$R/t_enroll" -lsqlite3
  run "$R/t_enroll" "$NODE" nodea
else
  echo "== integration: SKIPPED ($NODE unreachable) =="
fi

echo "== single write authority (D1 3.2, D4 1) =="
run tests/test_write_authority.sh

if [ $fail -eq 0 ]; then
  echo "ALL SUITES PASS"
else
  echo "SUITE FAILURES"
  exit 1
fi

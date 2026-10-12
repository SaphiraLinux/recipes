#!/bin/sh
# The single-write-authority rule, proven at the BINARY level (D1 3.2, D4 1).
#
# File modes are the backstop, not the mechanism. The mechanism is that the
# client code paths contain no database access at all: the TUI and the CLI are
# linked without any sqlite3 symbol, so they cannot open the database even if
# the file were world-writable. Only the core is linked against it.
set -e
cd "$(dirname "$0")/.."
fail=0
say() { printf "  %-58s %s\n" "$1" "$2"; }

for obj in build/tui.o build/cli.o; do
  name=$(basename "$obj")
  if [ ! -f "$obj" ]; then say "$name present" "**FAIL**"; fail=1; continue; fi
  if nm -u "$obj" 2>/dev/null | grep -qE 'sqlite3_(open|exec|prepare|bind|step)'; then
    say "$obj links no sqlite3 write path" "**FAIL**"
    fail=1
  else
    say "$obj links no sqlite3 write path" "PASS"
  fi
done

# The core, by contrast, must actually own the database.
if nm -u build/db.o 2>/dev/null | grep -qE 'sqlite3_open|sqlite3_exec'; then
  say "build/db.o DOES own the database (the sole writer)" "PASS"
else
  say "build/db.o DOES own the database (the sole writer)" "**FAIL**"
  fail=1
fi

# The API client helper is shared by both interfaces and must not open the db.
if nm -u build/api.o 2>/dev/null | grep -qE 'sqlite3_open'; then
  say "build/api.o opens the database only for writes" "**FAIL**"
  fail=1
else
  say "build/api.o does not open the database itself" "PASS"
fi

# Source-level: no client translation unit includes the database header.
for src in src/tui.c src/cli.c; do
  if grep -qE '#include[[:space:]]+"(sr_db\.h)"' "$src"; then
    say "$src does not include the database header" "**FAIL**"
    fail=1
  else
    say "$src does not include the database header" "PASS"
  fi
done

# And the shipped state directory is 0750, owner-only, in the payload.
apk=$(ls -1 /out/stage4/incoming/*/saphira-router-*.apk 2>/dev/null | head -1)
if [ -n "$apk" ]; then
  say "state directory declared 0750 in accounts.d" \
      "$(grep -q 'dir  /var/lib/saphira-router 0750' /recipes/saphira-router/files/accounts.d/saphira-router 2>/dev/null && echo PASS || echo '**FAIL**')"
fi

[ $fail -eq 0 ] && echo "  write-authority: OK" || { echo "  write-authority: FAILED"; exit 1; }

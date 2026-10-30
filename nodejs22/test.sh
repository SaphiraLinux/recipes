#!/bin/sh
# Saphira builder TEST stage for nodejs22 (Node 22).
#
# Executed by the builder as: /bin/sh test.sh
# with SAPHIRA_TEST_ROOT (disposable install root holding the just-built
# package) and SAPHIRA_PKG in the environment. Exit 0 iff no FAIL/ERROR.
#
# This driver runs the October-2026 CVE regression suite
# (test-security/), NOT the ordinary smoke tests (those live in
# recipe_build). Protocol per case, enforced here:
#   exit 0  PASS   - fixed behavior observed
#   exit 1  FAIL   - vulnerable/regressed behavior observed
#   exit 2  SKIP   - not applicable to this Node line (explicit, counted)
#   timeout/else ERROR - harness or environment failure (never a pass)
#
# Mirror note: test-security/ is duplicated in nodejs22 (builder runs
# each recipe's own tree; no cross-recipe references). Keep both in
# sync; the ONLY intended difference is the 105483 version gate below.
set -eu

BIN=node22
MAJOR=22
ROOT="${SAPHIRA_TEST_ROOT:?SAPHIRA_TEST_ROOT unset - must run under saphira-build TEST stage}"
NODE="$ROOT/usr/bin/$BIN"
CASES="$(dirname "$0")/test-security"

[ -x "$NODE" ] || { echo "ERROR: $NODE missing or not executable"; exit 2; }
echo "testing: $("$NODE" --version) ($BIN)"

PASS=0; FAIL=0; SKIP=0; ERROR=0
TMPBASE="$(mktemp -d)"

# run_case <id> <file> <timeout-s> <on-timeout: FAIL|ERROR> [args...]
# Extra node flags for one case travel via NODE_FLAGS (must precede the
# script on the command line, so they cannot be plain args).
run_case() {
	id="$1"; file="$2"; secs="$3"; on_timeout="$4"; shift 4
	echo "--- $id"
	set +e
	# shellcheck disable=SC2086
	out=$(timeout "$secs" "$NODE" ${NODE_FLAGS-} "$file" "$@" 2>&1)
	rc=$?
	set -e
	if [ "$rc" -eq 0 ]; then
		echo "PASS $id"
		PASS=$((PASS + 1))
	elif [ "$rc" -eq 2 ]; then
		echo "SKIP $id :: $out"
		SKIP=$((SKIP + 1))
	elif [ "$rc" -eq 124 ]; then
		echo "$on_timeout $id :: TIMEOUT after ${secs}s :: $out"
		if [ "$on_timeout" = FAIL ]; then FAIL=$((FAIL + 1)); else ERROR=$((ERROR + 1)); fi
	elif [ "$rc" -eq 1 ]; then
		echo "FAIL $id :: $out"
		FAIL=$((FAIL + 1))
	else
		echo "ERROR $id :: rc=$rc :: $out"
		ERROR=$((ERROR + 1))
	fi
}

# CVE-2026-105482: NUL rejection is fixed on every supported line.
run_case CVE-2026-105482 "$CASES/cve-2026-105482-dns-nul.js" 30 ERROR

# CVE-2026-105483: fullwidth-IP bypass is a 24/26-only regression.
# (Explicit gate: never demand it of Node 22, never silently skip it here.)
if [ "$MAJOR" -eq 24 ]; then
	run_case CVE-2026-105483 "$CASES/cve-2026-105483-tls-fullwidth.js" 30 ERROR
else
	echo "SKIP CVE-2026-105483 :: 24-only fix; line $MAJOR not affected"
	SKIP=$((SKIP + 1))
fi

run_case CVE-2026-106069 "$CASES/cve-2026-106069-tls-leading-zero.js" 30 ERROR
run_case CVE-2026-106072 "$CASES/cve-2026-106072-tls-numeric-san.js" 30 ERROR
# Brotli: a hung decoder is the vulnerability symptom, not a harness
# fault - timeout counts as FAIL here and only here.
run_case CVE-2026-111497 "$CASES/cve-2026-111497-brotli.js" 60 FAIL
run_case CVE-2026-105481 "$CASES/cve-2026-105481-keepalive.js" 30 ERROR
run_case CVE-2026-106074 "$CASES/cve-2026-106074-snapshot.js" 120 ERROR

# CVE-2026-106073: the permission fixture must live outside every grant
# except the one under test, and the case file itself must be readable
# under --permission, so it runs from inside the granted directory.
PERMROOT="$TMPBASE/perm"; mkdir -p "$PERMROOT/allowed" "$PERMROOT/secret"
echo data > "$PERMROOT/allowed/ok.txt"; echo data > "$PERMROOT/secret/no.txt"
cp "$CASES/cve-2026-106073-permission.js" "$PERMROOT/allowed/"
NODE_FLAGS="--permission --allow-fs-read=$PERMROOT/allowed" \
run_case CVE-2026-106073 "$PERMROOT/allowed/cve-2026-106073-permission.js" 30 ERROR "$PERMROOT"

# Live TLS wiring: full handshake through the fixed verifier.
run_case TLS-LIVE "$CASES/tls-live.js" 30 ERROR "$CASES"

rm -rf "$TMPBASE"
echo "RESULT: $PASS PASS, $SKIP SKIP, $FAIL FAIL, $ERROR ERROR"
[ "$FAIL" -eq 0 ] && [ "$ERROR" -eq 0 ]

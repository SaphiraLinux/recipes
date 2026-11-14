#!/bin/sh
# Sinew F4 benchmark driver: builds and runs the libc measurement suite.
#
# Usage (CWD anywhere; the script finds its own src/):
#   sh /recipes/libc-test/tests/sinew-bench-f4/bench-f4.sh [--scale N] [--link dynamic|static|both]
#
# Scratch lives under ${SAPHIRA_TMPDIR:-/build/tmp}; override SAPHIRA_TMPDIR
# on hosts where /build is not writable (e.g. minimer as non-root).
# CPU affinity pins to CPU 0 via taskset when available (recorded either way).
# Exit status: 0 when every binary's verify() passed; 1 when any check
# failed (performance numbers are data either way and are always written).
set -u

SCALE=1
LINK=both
while [ $# -gt 0 ]; do
	case "$1" in
	--scale=*) SCALE=${1#--scale=} ;;
	--scale) SCALE=$2; shift ;;
	--link=*) LINK=${1#--link=} ;;
	--link) LINK=$2; shift ;;
	*) echo "usage: $0 [--scale N] [--link dynamic|static|both]" >&2; exit 2 ;;
	esac
	shift
done
case "$LINK" in
dynamic | static | both) ;;
*) echo "usage: $0 [--scale N] [--link dynamic|static|both]" >&2; exit 2 ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${SAPHIRA_TMPDIR:-/build/tmp}/sinew-bench-f4-$$
if ! mkdir -p "$ROOT" 2>/dev/null; then
	echo "bench-f4: scratch $ROOT not writable;" >&2
	echo "bench-f4: set SAPHIRA_TMPDIR to a writable dir and rerun." >&2
	exit 2
fi
BIN="$ROOT/bin"
mkdir -p "$BIN"

CC=${CC:-cc}
CFLAGS="-O2 -fno-builtin"
STATIC_CC=/opt/saphira/musl-static/bin/musl-static-gcc

ENV_JSON="$ROOT/env.json"
{
	echo "{"
	printf '  "suite": "sinew-bench-f4", "host": "%s", ' "$(uname -n)"
	printf '"arch": "%s", ' "$(uname -m)"
	printf '"os": "%s", ' "$(uname -srm)"
	printf '"cpu": "%s", ' "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//;s/"/_/g')"
	printf '"mem_kb": "%s", ' "$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)"
	printf '"cc": "%s", ' "$($CC --version 2>/dev/null | head -1 | tr -d '\"')"
	printf '"cflags": "%s", ' "$CFLAGS"
	printf '"ldd": "%s", ' "$(ldd --version 2>&1 | head -1 | tr -d '\"')"
	printf '"scale": %s, ' "$SCALE"
	if command -v taskset >/dev/null 2>&1; then
		printf '"affinity": "taskset-c0", '
		TASKSET="taskset -c 0"
	else
		printf '"affinity": "unavailable", '
		TASKSET=""
	fi
	if [ -r /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq ]; then
		printf '"freq_khz": %s, ' "$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)"
	else
		printf '"freq_khz": "unavailable", '
	fi
	if [ -r /sys/devices/system/cpu/cpufreq/policy0/scaling_governor ]; then
		printf '"governor": "%s", ' "$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
	else
		printf '"governor": "unavailable", '
	fi
	printf '"static_cc": "%s"' "$(if [ -x "$STATIC_CC" ]; then echo present; else echo missing; fi)"
	echo ""
	echo "}"
} >"$ENV_JSON"

export BENCH_SCALE="$SCALE"
FAIL=0
OUT="$ROOT/results.jsonl"
cp "$ENV_JSON" "$ROOT/env-out.json"
: >"$OUT"

build_one() {
	src=$1
	base=$(basename "$src" .c)
	if [ "$LINK" = dynamic ] || [ "$LINK" = both ]; then
		if $CC $CFLAGS -DBENCH_LINK='"dynamic"' -o "$BIN/$base-dyn" "$src" -lm 2>"$ROOT/$base-dyn.log"; then
			echo "build ok $base dynamic"
		else
			echo "build FAIL $base dynamic (see $ROOT/$base-dyn.log)"
			FAIL=1
		fi
	fi
	if [ "$LINK" = static ] || [ "$LINK" = both ]; then
		if [ -x "$STATIC_CC" ]; then
			if $STATIC_CC $CFLAGS -DBENCH_LINK='"static"' -o "$BIN/$base-static" "$src" -lm 2>"$ROOT/$base-static.log"; then
				echo "build ok $base static"
			else
				echo "build FAIL $base static (see $ROOT/$base-static.log)"
				FAIL=1
			fi
		else
			echo "build SKIP $base static (musl-static-gcc missing)"
		fi
	fi
}

run_one() {
	bin=$1
	name=$(basename "$bin")
	if [ ! -x "$bin" ]; then
		return 0
	fi
	out=$($TASKSET "$bin" 2>"$ROOT/$name.stderr")
	rc=$?
	printf '%s\n' "$out" >>"$OUT"
	if [ $rc -ne 0 ]; then
		echo "verify FAIL $name (rc=$rc)"
		FAIL=1
	else
		echo "verify pass $name"
	fi
	if [ -s "$ROOT/$name.stderr" ]; then
		echo "--- stderr $name:"
		head -5 "$ROOT/$name.stderr"
	fi
}

for s in "$HERE"/src/m_*.c; do
	build_one "$s"
done

for b in "$BIN"/*; do
	[ -x "$b" ] || continue
	run_one "$b"
done

echo ""
echo "== summary =="
total=$(grep -c '"bench"' "$OUT" 2>/dev/null || true)
vfail=$(grep -c '"verify":"fail"' "$OUT" 2>/dev/null || true)
echo "bench lines: $total, verify=fail lines: $vfail"
echo "results: $OUT"
echo "env: $ENV_JSON"
echo "scratch kept at: $ROOT (remove when done)"
exit $FAIL

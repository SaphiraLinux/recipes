#!/bin/sh
# Audit test runner (final): builds each test static against the Saphira
# baseline tree and the patched tree (no host libc in the link), runs both,
# and records outputs for comparison. Crash-oriented cases run under
# ulimit+timeout; a baseline crash vs patched graceful handling IS signal.
# Exit status is always 0; evidence lives in per-test .out/.build-err files.
set -u
S=/build/tmp/musl-audit
BB=$S/b-baseline
BP=$S/b-patched
RB=$S/root-baseline
RP=$S/root-patched
OUT=$S/results
rm -rf "$OUT"
mkdir -p "$OUT"
CC=${CC:-gcc}
LG=$($CC -print-libgcc-file-name)

build_one() { # $1=test $2=tag $3=build-tree $4=root [$5...=extra cflags]
	name=$1; tag=$2; bt=$3; rt=$4; shift 4
	$CC -static -nostdlib -I "$rt/usr/include" \
		"$bt/lib/crt1.o" "$bt/lib/crti.o" "$S/tests/$name.c" \
		"$@" "$bt/lib/libc.a" "$LG" "$bt/lib/crtn.o" \
		-o "$OUT/$name.$tag" 2>"$OUT/$name.$tag.build-err" \
		|| {
			echo "BUILD-FAIL $name.$tag"
			return 1
		}
}

run_plain() { # $1=test $2=tag $3...=args
	name=$1; tag=$2; shift 2
	(cd "$OUT" && ./"$name.$tag" "$@" >"$name.$tag.out" 2>"$name.$tag.err")
	echo "$name.$tag rc=$?"
}

fails=0
for t in t1-scanf-printf t2-float-math t3-fnmatch t4-regcomp t5-scandir-qsort \
	t6-timer t7-time t8-misc t8-steps t8a-stdio t8b-misc t8c-wordexp \
	t9-iconv t10-tz t11-crash t12-bisect t13-strerror t14-volatile \
	t15-dns t16-cancel t17-pageguard t19-faultaddr t20-handler; do
	build_one $t base "$BB" "$RB" || fails=$((fails + 1))
	build_one $t patched "$BP" "$RP" || fails=$((fails + 1))
done
# Base-only no-crash variant of t8b (wcsrchr skipped) for the tail coverage.
build_one t8b-misc base-nc "$BB" "$RB" -DSKIP_WCSRCHR=1 || fails=$((fails + 1))
echo "build-failures=$fails"

run_plain t1-scanf-printf base
run_plain t1-scanf-printf patched
run_plain t2-float-math base
run_plain t2-float-math patched
run_plain t3-fnmatch base
run_plain t3-fnmatch patched
run_plain t4-regcomp base small
run_plain t4-regcomp patched small
run_plain t5-scandir-qsort base
run_plain t5-scandir-qsort patched
run_plain t7-time base "$OUT/tz-base.bin"
run_plain t7-time patched "$OUT/tz-patched.bin"
run_plain t8-misc base
run_plain t8-misc patched
run_plain t8-steps base
run_plain t8-steps patched
run_plain t8a-stdio base
run_plain t8a-stdio patched
run_plain t8b-misc base
run_plain t8b-misc patched
run_plain t8b-misc base-nc
run_plain t8c-wordexp base
run_plain t8c-wordexp patched
run_plain t9-iconv base
run_plain t9-iconv patched
run_plain t10-tz base America/New_York
run_plain t10-tz patched America/New_York
run_plain t11-crash base wcsrchr
run_plain t11-crash patched wcsrchr
run_plain t11-crash base memalign
run_plain t11-crash patched memalign
run_plain t12-bisect base
run_plain t12-bisect patched
run_plain t13-strerror base
run_plain t13-strerror patched
run_plain t14-volatile base
run_plain t14-volatile patched
run_plain t15-dns base smoke
run_plain t15-dns patched smoke
run_plain t16-cancel base
run_plain t16-cancel patched
run_plain t17-pageguard base
run_plain t17-pageguard patched
run_plain t19-faultaddr base
run_plain t19-faultaddr patched
run_plain t20-handler base
run_plain t20-handler patched

echo "--- t6-timer under timeout 10 (rc=124 means deadlock) ---"
(cd "$OUT" && timeout 10 ./t6-timer.base >t6-timer.base.out 2>&1; echo "base-timer rc=$?")
(cd "$OUT" && timeout 10 ./t6-timer.patched >t6-timer.patched.out 2>&1; echo "patched-timer rc=$?")
echo "--- t6-timer hang loop 30x timeout 3 ---"
(cd "$OUT" && h=0; for i in $(seq 1 30); do timeout 3 ./t6-timer.base >/dev/null 2>&1 || h=$((h+1)); done; echo "base hangs=$h/30")
(cd "$OUT" && h=0; for i in $(seq 1 30); do timeout 3 ./t6-timer.patched >/dev/null 2>&1 || h=$((h+1)); done; echo "patched hangs=$h/30")
echo "--- t4-regcomp alt/rep (bounded 1GB VA, 90s) ---"
(cd "$OUT" && ulimit -v 1048576; timeout 90 ./t4-regcomp.patched alt >t4-regcomp.patched.alt.out 2>&1; echo "patched-alt rc=$?")
(cd "$OUT" && ulimit -v 1048576; timeout 90 ./t4-regcomp.base alt >t4-regcomp.base.alt.out 2>&1; echo "base-alt rc=$?")
(cd "$OUT" && ulimit -v 1048576; timeout 90 ./t4-regcomp.patched rep >t4-regcomp.patched.rep.out 2>&1; echo "patched-rep rc=$?")
(cd "$OUT" && ulimit -v 1048576; timeout 90 ./t4-regcomp.base rep >t4-regcomp.base.rep.out 2>&1; echo "base-rep rc=$?")
echo DONE

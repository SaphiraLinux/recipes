#!/bin/sh

# Saphira Rust FFI bool ABI gate: a C caller must observe exact 0/1.
#
# Incident: Rust 1.99.0 miscompiled `extern "C" fn ... -> bool` on x86_64
# (rust-lang/rust#163911). The `zeroext` attribute was dropped from the i1
# return, so callees left garbage in bits 1-7 and a C caller observed e.g.
# 16 instead of 0. Fixed in 1.99.1 (PR #163917). Rust-to-Rust FFI tests
# could not see it (a 1.99.0 caller tested only bit 0), so this gate
# exercises the real C-to-Rust ABI with exact-value assertions.
#
# Deliberately behavioural, not textual: no `andb` grep. Optimisers may
# mask however they like provided bits 1-7 of the returned byte are 0.
# Both shapes from the issue report are covered, at opt-level 0 and 2
# (1.99.0 was broken at both).
#
# usage: rust-ffi-bool.sh (needs rustc with x86_64-akadata-linux-musl
#        and x86_64-akadata-linux-musl-gcc; operates on the live toolchain,
#        reads only the recipe tree for nothing -- this is a behaviour gate)

set -eu

fail()
{
	printf '%s\n' "rust-ffi-bool: $*" >&2
	exit 1
}

checks=0
ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

command -v rustc >/dev/null 2>&1 ||
	fail "rustc is not on PATH"
command -v x86_64-akadata-linux-musl-gcc >/dev/null 2>&1 ||
	fail "x86_64-akadata-linux-musl-gcc is not on PATH"
rustc --print target-list 2>/dev/null | grep -qx 'x86_64-akadata-linux-musl' ||
	fail "rustc does not enumerate x86_64-akadata-linux-musl"

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/rust-ffi-bool.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

cat > "$work/bool.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn rust_fn_returning_bool(flags: u8) -> bool {
    (flags & 0x1) == 0x1
}

#[no_mangle]
pub extern "C" fn rust_second_shape(x: u8) -> bool {
    (x & 1) == 1
}
EOF

cat > "$work/caller.c" <<'EOF'
#include <stdio.h>
#include <stdbool.h>

extern bool rust_fn_returning_bool(unsigned char);
extern bool rust_second_shape(unsigned char);

static const unsigned char inputs[] = { 0x00, 0x01, 0x10, 0xFF, 0x02 };
static const int wants[] = { 0, 1, 0, 1, 0 };

int main(void)
{
	int i, fails = 0;
	for (i = 0; i < 5; i++) {
		int a = (int)rust_fn_returning_bool(inputs[i]);
		int b = (int)rust_second_shape(inputs[i]);
		printf("in=0x%02x first=%d second=%d want=%d\n",
			inputs[i], a, b, wants[i]);
		if (a != wants[i] || b != wants[i] ||
			(a != 0 && a != 1) || (b != 0 && b != 1))
			fails = 1;
	}
	return fails;
}
EOF

for opt in 0 2; do
	rustc --edition=2021 --crate-type=staticlib --crate-name=rbool \
		--target x86_64-akadata-linux-musl -C opt-level="$opt" \
		-C panic=abort \
		--out-dir "$work" "$work/bool.rs" ||
		fail "rustc staticlib build failed at opt-level $opt"
	test -f "$work/librbool.a" ||
		fail "rustc did not emit librbool.a at opt-level $opt"
	x86_64-akadata-linux-musl-gcc "$work/caller.c" "$work/librbool.a" \
		-o "$work/caller-$opt" ||
		fail "C caller link failed at opt-level $opt"
	"$work/caller-$opt" > "$work/got-$opt.txt" ||
		fail "C caller observed a non-0/1 bool return at opt-level $opt (see below):
$(cat "$work/got-$opt.txt")"
	grep -q 'in=0x10 first=0 second=0 want=0' "$work/got-$opt.txt" ||
		fail "0x10 vector missing or wrong at opt-level $opt"
	grep -q 'in=0xff first=1 second=1 want=1' "$work/got-$opt.txt" ||
		fail "0xFF vector missing or wrong at opt-level $opt"
	ok "C caller observes exact 0/1 from both Rust shapes at opt-level $opt"
done

printf '%s\n' "rust-ffi-bool: OK ($checks checks)"

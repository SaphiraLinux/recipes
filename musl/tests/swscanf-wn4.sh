#!/bin/sh
# swscanf wide-input layer (Sinew WN4 / patch 0031).
# Tests the HOST libc: fails on musl without 0031 (wcsrtombs adapter
# manufactures EOF for any wide input unencodable in the thread locale),
# passes with 0031 applied. Hermetic scratch under SAPHIRA_TMPDIR.
#
# Coverage: C-locale %lc/%ls on non-ASCII wide input (W4a/W4c),
# partial ASCII+non-ASCII (W4e), %n accounting (W4f), long input
# past the old 256-byte refill (W4h), empty input EOF (W4i), UTF-8
# control (must pass before and after), narrow-%c C-locale failure
# preserved (W4d, both sides fail where wcrtomb genuinely fails).
set -eu
root=${SAPHIRA_TMPDIR:-/build/tmp}/swscanf-wn4-test-$$
mkdir -p "$root"
trap 'rm -rf "$root"' EXIT INT TERM
cat > "$root/t.c" <<'EOF'
#include <stdio.h>
#include <wchar.h>
#include <locale.h>
static int fails = 0;
static void check(int cond, const char *name) {
	if (!cond) { printf("FAIL %s\n", name); fails++; }
	else printf("ok %s\n", name);
}
int main(void) {
	wchar_t ws[512];
	char s[16];
	int r, n, i;
	/* C locale: the WN4 domain. */
	setlocale(LC_ALL, "C");
	ws[0] = (wchar_t)0xAAAAAAAA;
	r = swscanf(L"\xc3\xa9", L"%lc", ws);
	check(r == 1 && ws[0] == 0xC3, "C %lc non-ascii");
	for (i = 0; i < 8; i++) ws[i] = (wchar_t)0xAAAAAAAA;
	r = swscanf(L"\xc3\xa9", L"%ls", ws);
	check(r == 1 && ws[0] == 0xC3 && ws[1] == 0xA9 && ws[2] == 0,
		"C %ls non-ascii");
	ws[0] = ws[1] = (wchar_t)0xAAAAAAAA;
	r = swscanf(L"a\xc3", L"%lc%lc", ws, ws + 1);
	check(r == 2 && ws[0] == L'a' && ws[1] == 0xC3,
		"C partial ascii+non-ascii");
	ws[0] = (wchar_t)0xAAAAAAAA; n = -7;
	r = swscanf(L"a\xc3", L"%lc%n", ws, &n);
	check(r == 1 && ws[0] == L'a' && n == 1, "C %n accounting");
	for (i = 0; i < 300; i++) ws[i] = (wchar_t)0xE9;
	ws[300] = 0;
	{
		static wchar_t out[512];
		for (i = 0; i < 512; i++) out[i] = (wchar_t)0xBBBBBBBB;
		r = swscanf(ws, L"%ls", out);
		check(r == 1 && out[300] == 0 && out[299] == 0xE9,
			"C long input past refill");
	}
	ws[0] = (wchar_t)0xAAAAAAAA;
	r = swscanf(L"", L"%lc", ws);
	check(r == -1, "C empty input EOF");
	for (i = 0; i < 8; i++) s[i] = (char)0xAA;
	r = swscanf(L"\xc3", L"%c", s);
	check(r == -1, "C narrow %c still fails (wcrtomb)");
	/* UTF-8 control: passes with and without 0031. */
	setlocale(LC_ALL, "C.UTF-8");
	ws[0] = (wchar_t)0xAAAAAAAA;
	r = swscanf(L"\xc3\xa9", L"%lc", ws);
	check(r == 1 && ws[0] == 0xC3, "UTF-8 %lc control");
	if (fails) {
		printf("RESULT: %d FAILURES\n", fails);
		return 1;
	}
	printf("RESULT: ALL PASS\n");
	return 0;
}
EOF
cc -O2 -Wall -o "$root/t" "$root/t.c"
"$root/t" </dev/null

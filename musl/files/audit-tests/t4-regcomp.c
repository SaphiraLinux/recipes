/* t4: regcomp overflow guards (upstream 7813e911, plus BRE 40acb04b).
 * CAUTION: the big cases are crash-oriented (run under ulimit+timeout by
 * the runner). Exit status and return codes are the evidence. */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <regex.h>

static void t(const char *pat, size_t shown, int expect_ok)
{
	regex_t re;
	int r = regcomp(&re, pat, REG_EXTENDED);
	printf("regcomp len=%zu rc=%d expect_%s %s\n",
		shown, r, expect_ok ? "ok" : "err",
		(expect_ok == (r == 0)) ? "OK" : "DIFFER");
	if (r == 0) {
		regmatch_t m;
		int e = regexec(&re, "aaa", 0, &m, 0);
		printf("  regexec(aaa)=%d\n", e);
		regfree(&re);
	}
}

int main(int argc, char **argv)
{
	const char *mode = argc > 1 ? argv[1] : "small";
	if (!strcmp(mode, "small")) {
		t("(a|b)*abb", 9, 1);
		t("((a{5}){5}){5}", 15, 1);
		t("a{1,3}b+", 8, 1);
		/* Invalid BRE back-reference is rejected (no crash). */
		{
			regex_t re;
			int r = regcomp(&re, "\\1", 0);
			printf("regcomp BRE \\1 rc=%d (correct nonzero)\n", r);
			if (r == 0)
				regfree(&re);
		}
		return 0;
	}
	if (!strcmp(mode, "alt")) {
		/* n^2/4 transitions: overflow needs n ~ 1e5. */
		int n = 100000;
		size_t len = (size_t)2 * n + 4;
		char *p = malloc(len + 1);
		if (!p)
			return 2;
		p[0] = '(';
		for (int i = 0; i < n; i++) {
			p[1 + 2 * i] = 'a';
			p[1 + 2 * i + 1] = '|';
		}
		strcpy(p + 1 + 2 * n - 1, "a)*");
		t(p, len, 0);
		free(p);
		return 0;
	}
	if (!strcmp(mode, "rep")) {
		/* Positional overflow through nested repetitions. */
		t("(((a{255}){255}){255}){255}", 25, 0);
		return 0;
	}
	return 2;
}

/* Saphira sinew spot checks: directed F3/F4/F8 cases locking in
 * the validated arch behaviour. Full matrices live in the Sinew
 * harnesses; this is the fast release smoke (correctness only,
 * durations informational). */
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "test.h"


static int fails;

static void checkd(const char *name, double got, double want)
{
	if (!(got == want)) {
		t_error("%s: got %a want %a\n", name, got, want);
		fails++;
	}
}

static void checkstr(const char *h, const char *n, long want)
{
	char *p = strstr(h, n);
	long got = p ? (long)(p - h) : -1;
	if (got != want) {
		t_error("strstr offset %ld want %ld\n", got, want);
		fails++;
	}
}

int main(void)
{
	/* F3: directed floor/ceil + rint ties */
	checkd("floor(0.5)", floor(0.5), 0.0);
	checkd("floor(-0.5)", floor(-0.5), -1.0);
	checkd("ceil(0.5)", ceil(0.5), 1.0);
	checkd("rint(2.5)", rint(2.5), 2.0);
	checkd("rint(3.5)", rint(3.5), 4.0);
	/* F4: ties to even */
	checkd("nearbyint(2.5)", nearbyint(2.5), 2.0);
	checkd("nearbyint(3.5)", nearbyint(3.5), 4.0);
	checkd("nearbyint(-0.5)", nearbyint(-0.5), -0.0);
	/* F8: 2/3/4-byte needles incl. absent + 1B/5B controls */
	checkstr("abcXXXXXXdef", "bc", 1);
	checkstr("abcXXXXXXdef", "abcXX", 0);
	checkstr("abcXXXXXXdef", "XXXX", 3);
	checkstr("abcXXXXXXdef", "XXXXdef", 5);
	checkstr("abcXXXXXXdef", "zz", -1);
	checkstr("abcXXXXXXdef", "e", 10);
	checkstr("abcXXXXXXdefXXXXXXXXXX", "XXXXdefXXX", 5);
	if (fails)
		return 1;
	return t_status;
}

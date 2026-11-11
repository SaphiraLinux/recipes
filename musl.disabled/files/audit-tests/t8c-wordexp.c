/* t8c: wordexp + popen smoke (upstream 235f7289, 331cf270, 38e04447,
 * f21a9653). */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <wordexp.h>

int main(void)
{
	wordexp_t w;
	int r = wordexp("$*", &w, 0);
	printf("wordexp-star: r=%d n=%zu (correct n=0)\n", r, r ? 0 : w.we_wordc);
	if (!r)
		wordfree(&w);
	r = wordexp(")", &w, 0);
	printf("wordexp-bad: r=%d (correct nonzero, stderr intact below)\n", r);
	if (!r)
		wordfree(&w);
	fprintf(stderr, "wordexp-stderr: intact\n");

	FILE *f = popen("echo hi", "r");
	char l[16] = { 0 };
	if (f) {
		fgets(l, sizeof l, f);
		pclose(f);
	}
	printf("popen-smoke: %s", l);
	return 0;
}

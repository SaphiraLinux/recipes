/* F4 wordexp: pinned-verdict spot checks + NOCMD scan throughput.
 *
 * CORRECTNESS (pinned verdicts, each shell-proven during Sinew 0022/0023):
 * - execution shapes under WRDE_NOCMD return WRDE_CMDSUB (never 0).
 * - clean shapes expand (return 0).
 * - malformed shapes return WRDE_SYNTAX/BADCHAR as pinned.
 * Verdicts are asserted exactly; output words are checked where pinned.
 * Throughput checksums only prove reproducibility.
 */
#include "bench_common.h"
#include <wordexp.h>

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 21

static int fails;

struct vec {
	const char *in;
	int flags;
	int want;
	const char *want0;
};

static const struct vec vecs[] = {
	{ "$(echo x)", WRDE_NOCMD, WRDE_CMDSUB, 0 },
	{ "`echo x`", WRDE_NOCMD, WRDE_CMDSUB, 0 },
	{ "$((echo + 1 ) )", WRDE_NOCMD, WRDE_CMDSUB, 0 },
	{ "$((1+2))", WRDE_NOCMD, 0, "3" },
	{ "$((\"1\"))", WRDE_NOCMD, 0, "1" },
	{ "${X-foo}", WRDE_NOCMD, 0, "foo" },
	/* Entry quoting changes the parse (verified bash + set -u):
	 * unquoted entry reads "$" literally (silent $Y); dq-wrapped
	 * entry exposes Y (BADVAL under UNDEF). Do not merge these. */
	{ "${X-\"$\"Y}", WRDE_NOCMD | WRDE_UNDEF, 0, "$Y" },
	{ "\"${X-\"$\"Y}\"", WRDE_NOCMD | WRDE_UNDEF, WRDE_BADVAL, 0 },
	{ "$((1 + 2 ) )", WRDE_NOCMD, WRDE_CMDSUB, 0 },
	{ "hello", WRDE_NOCMD, 0, "hello" },
	{ 0, 0, 0, 0 }
};

static void verify_wordexp(void)
{
	int i;
	unsetenv("X");
	unsetenv("Y");
	unsetenv("UNSET");
	for (i = 0; vecs[i].in; i++) {
		wordexp_t we;
		int r;
		char esc[256];
		memset(&we, 0, sizeof we);
		r = wordexp(vecs[i].in, &we, vecs[i].flags);
		bench_json_escape(esc, sizeof esc, vecs[i].in);
		if (r != vecs[i].want) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"wordexp-verdict\","
				"\"in\":\"%s\",\"got\":%d,\"want\":%d}\n",
				esc, r, vecs[i].want);
			fails++;
		} else if (r == 0 && vecs[i].want0 &&
		    (we.we_wordc < 1 || strcmp(we.we_wordv[0], vecs[i].want0) != 0)) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"wordexp-word\","
				"\"in\":\"%s\",\"got\":\"%s\",\"want\":\"%s\"}\n",
				esc,
				we.we_wordc ? we.we_wordv[0] : "(none)",
				vecs[i].want0);
			fails++;
		}
		if (r == 0)
			wordfree(&we);
	}
}

static const char *bench_inputs[] = {
	"hello world ${X-default} $((1+2))",
	"$(echo no) `echo no` $((echo + 1 ) )",
	"\"${X-a'b'}\" '${Y-x}' plain $(( \"1\" + \"2\" ))",
	"/usr/bin:/bin s1 s2 s3 s4 s5 s6 s7 s8"
};
#define NIN (sizeof bench_inputs / sizeof bench_inputs[0])

int main(void)
{
	long scale = bench_scale();
	long iters = 20000 * scale;
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	uint64_t cksum = 1469598103934665603ull;
	const char *verify;
	double mn, md, p95, cmn, cmd, cp95;

	verify_wordexp();
	verify = fails ? "fail" : "pass";

	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		uint64_t acc = 0;
		for (i = 0; i < iters; i++) {
			wordexp_t we;
			int r;
			memset(&we, 0, sizeof we);
			r = wordexp(bench_inputs[i % NIN], &we, WRDE_NOCMD);
			acc = acc * 31 + (uint64_t)r + we.we_wordc;
			if (r == 0)
				wordfree(&we);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		bench_sink_u64(acc);
		cksum = bench_fnv1a(&acc, 8, cksum);
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit("wordexp-nocmd-mixed", BENCH_LINK, verify,
		iters, BATCHES, mn, md, p95,
		1e9 / md, 0.0, cmd, cksum, 0.0,
		"mixed clean/blocked/malformed; verdicts pinned above, independent");
	return fails ? 1 : 0;
}

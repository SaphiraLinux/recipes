/* t9: iconv gb18030 standalone (upstream 67219f01): correctness plus
 * bulk-conversion timing. Lets the baseline's bulk cost be measured
 * without the t8 crash getting in the way. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <iconv.h>

int main(void)
{
	iconv_t cd = iconv_open("UTF-8", "GB18030");
	char in[] = "T\xa8\xa4";
	char out[16] = { 0 };
	char *ip = in, *op = out;
	size_t il = sizeof in - 1, ol = sizeof out;
	size_t r = iconv(cd, &ip, &il, &op, &ol);
	printf("iconv-gb18030: r=%zu out=%s\n", r, out);
	iconv_close(cd);

	static char big[800000];
	for (int i = 0; i < 200000; i++) {
		big[4 * i] = '\x82';
		big[4 * i + 1] = '\x35';
		big[4 * i + 2] = '\x8a';
		big[4 * i + 3] = '\x38';
	}
	static char ob[1200000];
	cd = iconv_open("UTF-8", "GB18030");
	ip = big;
	op = ob;
	il = sizeof big;
	ol = sizeof ob;
	clock_t c0 = clock();
	r = iconv(cd, &ip, &il, &op, &ol);
	clock_t c1 = clock();
	printf("iconv-bulk: r=%zu left=%zu ms=%ld\n", r, il,
		(long)((c1 - c0) * 1000 / CLOCKS_PER_SEC));
	iconv_close(cd);
	return 0;
}

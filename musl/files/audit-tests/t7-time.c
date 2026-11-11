/* t7: time/locale (upstream c2021b77, 0572555d, c0c6e62a, 1a094684).
 * Includes a crafted minimal TZif v1 file: the unpatched tree misreads it
 * as v2 (wrong second-header parse), the patched tree honours the NUL
 * version byte. TZ path is passed via argv[1] (writable scratch file).
 */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <limits.h>
#include <errno.h>
#include <wchar.h>
#include <unistd.h>

/* Minimal TZif v1 with two transitions: t=0 -> type1 (off 3600),
 * t=7200 -> type0 (off 0). localtime(1) must be 01:00 +3600: it lands on
 * a non-final transition entry. A reader that misparses the file as v2
 * seeks its second header past EOF into zero padding and falls back. */
static const unsigned char tzif1[] = {
	'T', 'Z', 'i', 'f', 0x00,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0,		/* ttisgmtcnt */
	0, 0, 0, 0,		/* ttisstdcnt */
	0, 0, 0, 0,		/* leapcnt */
	0, 0, 0, 2,		/* timecnt */
	0, 0, 0, 2,		/* typecnt */
	0, 0, 0, 2,		/* charcnt */
	0, 0, 0, 0,		/* trans time 0 */
	0, 0, 0x1c, 0x20,	/* trans time 7200 */
	1, 0,			/* trans type indices */
	0, 0, 0, 0, 0, 0,	/* type 0: off 0 */
	0, 0, 0x0e, 0x10, 0, 0,	/* type 1: off 3600 */
	0, 0			/* names */
};

int main(int argc, char **argv)
{
	/* mktime must normalise extreme tm_mday without overflowing. */
	struct tm tm = { 0 };
	tm.tm_year = 120;
	tm.tm_mon = 0;
	tm.tm_mday = INT_MIN;
	tm.tm_hour = 12;
	errno = 0;
	time_t t = mktime(&tm);
	printf("mktime-INT_MIN-mday: t=%lld errno=%d\n", (long long)t, errno);

	/* strptime %Z must not read tzname[] out of bounds. */
	memset(&tm, 0, sizeof tm);
	setenv("TZ", "EST5", 1);
	tzset();
	char *r = strptime("EST", "%Z", &tm);
	printf("strptime-Z: %s\n", r ? "parsed" : "NULL");

	/* Tag range end (U+E007F) has width 0, not -1. */
	printf("wcwidth-U+E007F: %d (correct 0)\n", wcwidth(0xE007F));

	if (argc > 1) {
		FILE *f = fopen(argv[1], "wb");
		if (!f) {
			printf("tzif-write: FAIL\n");
			return 1;
		}
		fwrite(tzif1, 1, sizeof tzif1, f);
		fclose(f);
		setenv("TZ", argv[1], 1);
		tzset();
		time_t t0 = 1;
		struct tm *lt = localtime(&t0);
		if (lt)
			printf("tzif-v1: %04d-%02d-%02d %02d:%02d UTC-offset=%ld (correct 1970-01-01 01:00 off 3600)\n",
				lt->tm_year + 1900, lt->tm_mon + 1,
				lt->tm_mday, lt->tm_hour, lt->tm_min,
				(long)lt->tm_gmtoff);
		else
			printf("tzif-v1: localtime NULL\n");
	}
	return 0;
}

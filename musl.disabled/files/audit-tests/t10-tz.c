/* t10: TZ harness validation with the live zoneinfo db, then the audit
 * v1 fixture. Proves the TZ-file path works before judging the fix. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char **argv)
{
	const char *zone = argc > 1 ? argv[1] : "America/New_York";
	setenv("TZ", zone, 1);
	tzset();
	time_t t0 = 1;
	struct tm *lt = localtime(&t0);
	if (lt)
		printf("zone %s: %04d-%02d-%02d %02d:%02d off=%ld\n", zone,
			lt->tm_year + 1900, lt->tm_mon + 1, lt->tm_mday,
			lt->tm_hour, lt->tm_min, (long)lt->tm_gmtoff);
	else
		printf("zone %s: localtime NULL\n", zone);
	return 0;
}

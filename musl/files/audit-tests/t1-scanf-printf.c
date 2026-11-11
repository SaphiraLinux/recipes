/* t1: scanf/printf/asprintf/swprintf behaviour (upstream 7d7b03b8, c2541fd5,
 * 9ec8ef2c, 3594657b, be5ba569, 249a86c1). Static-linked against the tree
 * under test; no host libc involved. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <wchar.h>

int main(void)
{
	setlocale(LC_ALL, "C.UTF-8");

	/* INT_MIN asterisk field width: must be an output error, not UB. */
	char buf[64];
	errno = 0;
	int r = snprintf(buf, sizeof buf, "%*d", INT_MIN, 42);
	printf("printf-intmin: r=%d errno=%d\n", r, errno);

	/* asprintf EILSEQ (lone surrogate): result pointer handling. */
	char *p = (char *)0x1234;
	errno = 0;
	r = asprintf(&p, "%lc", (wint_t)0xDC00);
	printf("asprintf-eilseq: r=%d p=%p errno=%d\n", r, (void *)p, errno);
	if (p && p != (char *)0x1234)
		free(p);

	/* Allocated %ms with a multibyte UTF-8 character. */
	char *q = 0;
	errno = 0;
	r = sscanf("\xc3\xa9x", "%ms", &q);
	printf("scanf-ms: r=%d q=%s\n", r, q ? q : "(null)");
	free(q);

	/* Huge %mlc width: must fail gracefully, never crash. */
	wchar_t *w = 0;
	errno = 0;
	r = sscanf("AB", "%2147483647mlc", &w);
	printf("scanf-mlc-huge: r=%d\n", r);
	free(w);

	/* swprintf truncation must set EOVERFLOW. */
	wchar_t wb[2];
	errno = 0;
	r = swprintf(wb, 2, L"hello");
	printf("swprintf-trunc: r=%d errno=%d\n", r, errno);

	return 0;
}

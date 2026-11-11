/* t3: fnmatch corrections (upstream be5fd367, b1efda5b, cb037c46,
 * c4e1bb39). Each line states the expected (correct) result. */
#include <stdio.h>
#include <fnmatch.h>
#include <locale.h>

static void t(const char *pat, const char *str, int flags, int expect)
{
	int r = fnmatch(pat, str, flags);
	printf("fnmatch pat<%s> str<%s> flags=0x%x -> %d expect=%d %s\n",
		pat, str, flags, r, expect, r == expect ? "OK" : "DIFFER");
}

int main(void)
{
	setlocale(LC_ALL, "C.UTF-8");
	/* Reversed range must not match its start character. */
	t("[z-a]", "z", 0, FNM_NOMATCH);
	/* Escaped leading '.' satisfies FNM_PERIOD. */
	t("\\.", ".", FNM_PERIOD, 0);
	/* Invalid byte after a complete match is not end-of-string. */
	t("a", "a\xff", 0, FNM_NOMATCH);
	/* Multibyte range endpoint advances correctly. */
	t("[\xc3\xa9]x", "\xc3\xa9x", 0, 0);
	/* Sanity: ordinary matching still works. */
	t("*", "abc", 0, 0);
	t("a*b", "axxb", 0, 0);
	t("[a-c]x", "bx", 0, 0);
	return 0;
}

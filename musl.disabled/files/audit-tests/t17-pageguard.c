/* t17: page-guard proof of the wcsrchr OOB read (upstream 15a1155e).
 * Places L"hello world" so its first wchar sits exactly at a page
 * boundary with the page below mapped PROT_NONE. The unpatched
 * translation unit (built -O2) reads s[-1] before its bound check
 * (the invalid pointer is dereferenced, not merely formed) ->
 * deterministic SIGSEGV. The fixed loop tests p==s first -> clean.
 * The mapping address is runtime-known only. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <unistd.h>
#include <sys/mman.h>

int main(void)
{
	long ps = sysconf(_SC_PAGESIZE);
	size_t nbytes = 12 * sizeof(wchar_t); /* 11 chars + NUL */
	unsigned char *map = mmap(0, (size_t)3 * ps, PROT_READ | PROT_WRITE,
		MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (map == MAP_FAILED) {
		printf("mmap-fail\n");
		return 2;
	}
	if (mprotect(map, (size_t)ps, PROT_NONE) != 0) {
		printf("mprotect-fail\n");
		return 2;
	}
	wchar_t *s = (wchar_t *)(map + ps); /* page start, void below */
	memcpy(s, L"hello world", nbytes);
	volatile wchar_t v = s[0];
	(void)v;
	void *p = wcsrchr(s, L'z');
	printf("wcsrchr-guard: %p (correct nil, no crash)\n", p);
	return 0;
}

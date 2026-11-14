/* Saphira guard boundaries: libc string/mem functions must stay
 * inside their objects. A 3-page arena has PROT_NONE guards around
 * one RW page; touching any byte of the middle page (including the
 * edges) must not fault, and results must be exact. A fault kills
 * this binary, which the runner reports as ERROR (never silent). */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include "test.h"


int main(void)
{
	long ps = sysconf(_SC_PAGESIZE);
	unsigned char *arena, *mid;
	size_t i;
	if (ps <= 0) {
		t_error("no page size\n");
		return 1;
	}
	arena = mmap(0, (size_t)ps * 3, PROT_READ | PROT_WRITE,
		     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (arena == MAP_FAILED) {
		t_error("mmap failed\n");
		return 1;
	}
	if (mprotect(arena, (size_t)ps, PROT_NONE) ||
	    mprotect(arena + (size_t)ps * 2, (size_t)ps, PROT_NONE)) {
		t_error("guard setup failed\n");
		return 1;
	}
	mid = arena + (size_t)ps;
	/* fill the middle page with 'A' (cannot form the xyz probe),
	 * leaving the last byte NUL for the strlen check */
	memset(mid, 'A', (size_t)ps);
	mid[(size_t)ps - 1] = 0;
	/* strlen across the page up to the last byte */
	if (strlen((char *)mid) != (size_t)ps - 1) {
		t_error("strlen edge wrong\n");
		return 1;
	}
	/* memcpy of the whole page, destination elsewhere */
	{
		static unsigned char dst[8192];
		if ((size_t)ps > sizeof dst) {
			t_error("page too big for static dst\n");
			return 1;
		}
		memcpy(dst, mid, (size_t)ps);
		if (memcmp(dst, mid, (size_t)ps)) {
			t_error("memcpy edge mismatch\n");
			return 1;
		}
	}
	/* strstr needle at the very end of the page */
	mid[(size_t)ps - 4] = 'x';
	mid[(size_t)ps - 3] = 'y';
	mid[(size_t)ps - 2] = 'z';
	{
		char *p = strstr((char *)mid, "xyz");
		if (!p || p != (char *)mid + ps - 4) {
			t_error("strstr edge wrong\n");
			return 1;
		}
	}
	/* absent needle scans the page without touching guards */
	if (strstr((char *)mid, "\x01\x02\x03\x04")) {
		t_error("absent needle found\n");
		return 1;
	}
	munmap(arena, (size_t)ps * 3);
	return t_status;
}

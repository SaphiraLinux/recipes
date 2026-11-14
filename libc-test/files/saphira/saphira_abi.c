/* Saphira ABI: required symbols resolve via dlsym(RTLD_DEFAULT).
 * A missing symbol means the installed libc cannot link the program
 * that needs it. PASS = every required symbol resolves. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include "test.h"

static const char *need[] = {
	/* libc core */
	"printf", "malloc", "free", "memcpy", "memmove", "memset",
	"strlen", "strstr", "strcmp", "open", "read", "write", "close",
	"fork", "waitpid", "exit",
	/* libm */
	"floor", "floorf", "ceil", "ceilf", "trunc", "truncf",
	"rint", "rintf", "nearbyint", "nearbyintf",
	"sin", "cos", "sqrt", "pow", "floor",
	/* threads */
	"pthread_create", "pthread_join", "pthread_mutex_lock",
	"pthread_cond_wait",
	/* dynamic loading itself */
	"dlopen", "dlsym", "dlclose",
	/* networking + misc used across the suite */
	"getaddrinfo", "socket", "mmap", "mprotect",
	"sigaction", "clock_gettime",
	0
};


int main(void)
{
	int i, missing = 0;
	for (i = 0; need[i]; i++) {
		void *p = dlsym(RTLD_DEFAULT, need[i]);
		if (!p) {
			t_error("missing symbol: %s\n", need[i]);
			missing++;
		}
	}
	if (missing)
		t_error("%d required symbols missing\n", missing);
	return t_status;
}

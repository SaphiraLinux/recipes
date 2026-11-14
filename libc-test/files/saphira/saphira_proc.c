/* Saphira processes/signals: fork + waitpid status propagation,
 * and sigaction + kill to self. No exec, no shell. */
#include <signal.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "test.h"


static volatile sig_atomic_t got;

static void onusr(int s)
{
	(void)s;
	got = 1;
}

int main(void)
{
	pid_t p;
	int st;
	struct sigaction sa;

	p = fork();
	if (p < 0) {
		t_error("fork failed\n");
		return 1;
	}
	if (p == 0)
		_exit(42);
	if (waitpid(p, &st, 0) != p) {
		t_error("waitpid failed\n");
		return 1;
	}
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 42) {
		t_error("child status wrong: %d\n", st);
		return 1;
	}

	sa.sa_handler = onusr;
	sa.sa_flags = 0;
	sigemptyset(&sa.sa_mask);
	if (sigaction(SIGUSR1, &sa, 0)) {
		t_error("sigaction failed\n");
		return 1;
	}
	if (kill(getpid(), SIGUSR1)) {
		t_error("kill failed\n");
		return 1;
	}
	if (!got) {
		t_error("handler never ran\n");
		return 1;
	}
	return t_status;
}

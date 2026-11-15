#!/bin/sh
# clone3 raw primitive smoke (Sinew 0015).
# Tests the HOST static toolchain: fails to LINK without 0015 (__clone3
# is hidden: absent from the DSO, present only in the static archive via
# the patch's new src/linux/clone3.c), passes with it applied.
# Hermetic scratch under SAPHIRA_TMPDIR.
#
# Design notes (see Item 9 findings):
# - Raw syscall() testing would BYPASS the patch: the kernel silently
#   accepts explicit-stack combinations that __clone3 rejects with
#   EINVAL. The test must call the hidden symbol, hence static-only.
# - The EINVAL guard is pure userspace: it runs on ANY kernel, so the
#   guard cases never skip. Only the fork round-trip and the size=0
#   pass-through need a live clone3: ENOSYS (pre-5.3) or EPERM
#   (seccomp/policy) skip those two cases explicitly, never the guard.
# - Rejected calls must not fork: a pipe + O_NONBLOCK read proves no
#   child wrote (EAGAIN). A broken guard would return a pid or a
#   different errno, both FAIL, never skip.
set -eu
# Static-only: __clone3 is hidden (absent from the DSO), so the test
# must link the static archive. Prefer musl-static-gcc from PATH, fall
# back to its well-known install location, else skip honestly.
if command -v musl-static-gcc >/dev/null 2>&1; then
	TC=musl-static-gcc
elif [ -x /opt/saphira/musl-static/bin/musl-static-gcc ]; then
	TC=/opt/saphira/musl-static/bin/musl-static-gcc
else
	echo "SKIP no static toolchain (need musl-static-gcc: __clone3 is hidden)"
	exit 0
fi
root=${SAPHIRA_TMPDIR:-/build/tmp}/clone3-smoke-test-$$
mkdir -p "$root"
trap 'rm -rf "$root"' EXIT INT TERM
cat > "$root/t.c" <<'EOF'
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

/* Mirrors src/linux/clone3.c (stable kernel ABI, append-only). */
struct clone_args {
	unsigned long long flags;
	unsigned long long pidfd;
	unsigned long long child_tid;
	unsigned long long parent_tid;
	unsigned long long exit_signal;
	unsigned long long stack;
	unsigned long long stack_size;
	unsigned long long tls;
	unsigned long long set_tid;
	unsigned long long set_tid_size;
	unsigned long long cgroup;
};

extern long __clone3(struct clone_args *args, size_t size);

static int fails = 0;
static void check(int cond, const char *name) {
	if (!cond) { printf("FAIL %s (errno=%d)\n", name, errno); fails++; }
	else printf("ok %s\n", name);
}

int main(void) {
	struct clone_args a;
	int live = 1; /* cleared when the kernel cannot run clone3 */

	/* Availability gate: fork-like child, no stack. */
	memset(&a, 0, sizeof a);
	a.exit_signal = SIGCHLD;
	errno = 0;
	{
		long pid = __clone3(&a, sizeof a);
		int e = errno;
		if (pid == 0)
			_exit(42); /* child returns here: exit immediately */
		if (pid < 0 && (e == ENOSYS || e == EPERM)) {
			printf("SKIP fork round-trip (%s); guard cases still run\n",
			       e == ENOSYS ? "ENOSYS: pre-5.3 kernel" : "EPERM: syscall policy");
			live = 0;
		} else if (pid <= 0) {
			errno = e;
			check(0, "fork-child");
			live = 0;
		} else {
			int st = 0;
			pid_t w;
			do { w = waitpid((pid_t)pid, &st, 0); }
			while (w < 0 && errno == EINTR);
			check(w == pid && WIFEXITED(st) && WEXITSTATUS(st) == 42,
			      "fork-child");
		}
	}

	/* Guard: explicit stack rejected without forking (kernel-independent).
	 * NOTE raw convention: __clone3 returns -errno directly and never
	 * sets errno (callers apply __syscall_ret themselves). */
	{
		int p[2];
		if (pipe(p) == 0) {
			fcntl(p[0], F_SETFL, O_NONBLOCK);
			memset(&a, 0, sizeof a);
			a.exit_signal = SIGCHLD;
			a.stack = 0x1;
			errno = 0;
			{
				long r = __clone3(&a, sizeof a);
				int e = errno;
				char buf[1];
				ssize_t n;
				int re;
				errno = e;
				check(r == -EINVAL && e == 0, "stack-rejected");
				n = read(p[0], buf, sizeof buf);
				re = errno;
				errno = re;
				check(n < 0 && re == EAGAIN, "stack-no-fork");
			}
			memset(&a, 0, sizeof a);
			a.exit_signal = SIGCHLD;
			a.stack_size = 4096;
			errno = 0;
			{
				long r = __clone3(&a, sizeof a);
				int e = errno;
				char buf[1];
				ssize_t n;
				int re;
				errno = e;
				check(r == -EINVAL && e == 0, "stacksize-rejected");
				n = read(p[0], buf, sizeof buf);
				re = errno;
				errno = re;
				check(n < 0 && re == EAGAIN, "stacksize-no-fork");
			}
			close(p[0]);
			close(p[1]);
		}
	}

	/* Pass-through: size=0 reaches the kernel (needs live clone3). */
	if (live) {
		memset(&a, 0, sizeof a);
		a.exit_signal = SIGCHLD;
		errno = 0;
		{
			long r = __clone3(&a, 0);
			int e = errno;
			if (r < 0 && (e == ENOSYS || e == EPERM)) {
				printf("SKIP size-zero (%s)\n",
				       e == ENOSYS ? "ENOSYS" : "EPERM");
			} else {
				errno = e;
				check(r == -EINVAL && e == 0, "size-zero");
			}
		}
	} else {
		printf("SKIP size-zero (no live clone3)\n");
	}

	if (fails) {
		printf("RESULT: %d FAILURES\n", fails);
		return 1;
	}
	printf("RESULT: ALL PASS\n");
	return 0;
}
EOF
$TC -O2 -Wall -o "$root/t" "$root/t.c"
"$root/t" </dev/null

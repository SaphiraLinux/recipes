# Saphira Linux
# Copyright (c) 2026 AKADATA LIMITED
# SPDX-License-Identifier: MIT
#!/bin/sh
# NSS user/group fixture matrix (Sinew Item 15).
# Hermetic regression for the passwd/group/shadow lookup family:
# the probe runs inside a user+mount namespace with fixture
# passwd, group and shadow files bind-mounted over /etc (plus the
# nsswitch fixture where that mount point exists — some hosts ship
# no /etc/nsswitch.conf); the host account databases are never
# read and never written. Static and dynamic linkages both run
# where the static toolchain is present.
#
# Coverage: 18 checks x clean/malformed phases — byname/byuid
# lookups with exact field checks, miss-is-NULL (no errno assertion:
# the value varies across implementations, see getpwnam(3) NOTES),
# reentrant hit/miss/ERANGE, group members, getgrouplist exact list
# and small-buffer count, fixture shadow fields, enumeration order
# and count, fgetpwent on the bound-over path. initgroups is
# deliberately excluded: it calls setgroups(2), a process-global
# side effect whose EPERM behaviour varies under sandboxing.
# sulogin-style daemons are out of scope for a PASS/FAIL probe.
#
# RED check (the harness must fail loudly on wrong expectations):
# change any expected constant below (e.g. uid 61001 -> 61999) and
# the run must report FAIL with a non-zero exit. Verified at landing.
# Namespace unavailable -> SKIP (exit 0), never a false FAIL.
set -eu
if ! unshare --user --map-root-user --mount true 2>/dev/null; then
	echo "SKIP user+mount namespaces unavailable (need unshare userns for fixture isolation)"
	exit 0
fi
if [ -n "${SAPHIRA_TMPDIR:-}" ]; then
	scratch_base=$SAPHIRA_TMPDIR
elif [ -d /build/tmp ] && [ -w /build/tmp ]; then
	scratch_base=/build/tmp
else
	scratch_base=/tmp
fi
root=$scratch_base/nss-fixture-test-$$
mkdir -p "$root/fix"
trap 'rm -rf "$root"' EXIT INT TERM
CC=${1:-cc}

# Clean fixture: two users, two groups, locked shadow passwords.
# UIDs/GIDs are synthetic (61xxx) and never touch host databases.
cat > "$root/fix/passwd.clean" <<'EOF'
sinew-u1:x:61001:61001:Sinew One:/nonexistent:/bin/false
sinew-u2:x:61002:61002:Sinew Two With A Deliberately Long Gecos Field To Exercise Buffer Growth Past Two Hundred And Fifty Six Characters Padding Padding Padding:/nonexistent:/bin/false
EOF
cat > "$root/fix/group.clean" <<'EOF'
sinew-g1:x:61101:sinew-u1
sinew-g2:x:61102:sinew-u1,sinew-u2
EOF
cat > "$root/fix/shadow.clean" <<'EOF'
sinew-u1:!:19000:0:99999:7:::
sinew-u2:*:19000:0:99999:7:::
EOF
# Malformed fixture: garbage line first, then the good entries.
cat > "$root/fix/passwd.bad" <<'EOF'
:::not-a-valid-entry:::
sinew-u1:x:61001:61001:Sinew One:/nonexistent:/bin/false
sinew-u2:x:61002:61002:Sinew Two:/nonexistent:/bin/false
EOF
cat > "$root/fix/group.bad" <<'EOF'
@@@garbage@@@
sinew-g1:x:61101:sinew-u1
sinew-g2:x:61102:sinew-u1,sinew-u2
EOF
cp "$root/fix/shadow.clean" "$root/fix/shadow.bad"
printf 'passwd: files\ngroup: files\nshadow: files\n' > "$root/fix/nsswitch.conf"

cat > "$root/t.c" <<'EOF'
#define _GNU_SOURCE /* getgrouplist/setpwent need BSD/GNU visibility;
		     * the POSIX.1-2008 entry points need only 200809L */
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <shadow.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
static int fails = 0;
static void check(int cond, const char *name) {
	int e = errno;
	if (!cond) { printf("FAIL %s (errno=%d)\n", name, e); fails++; }
	else printf("ok %s\n", name);
}
int main(void) {
	struct passwd *pw; struct group *gr; struct spwd *sp;

	/* Lookup hits: exact fields. */
	errno = 0; pw = getpwnam("sinew-u1");
	check(pw && pw->pw_uid == 61001 && pw->pw_gid == 61001 &&
	      !strcmp(pw->pw_name, "sinew-u1") &&
	      !strcmp(pw->pw_dir, "/nonexistent") &&
	      !strcmp(pw->pw_shell, "/bin/false"), "byname-fields");
	errno = 0; pw = getpwuid(61002);
	check(pw && !strcmp(pw->pw_name, "sinew-u2"), "byuid-name");
	/* Miss: NULL required, errno recorded only (varies by system). */
	{
		int e;
		errno = 0; pw = getpwnam("no-such-user-sinew"); e = errno;
		printf("info miss errno=%d\n", e);
		check(pw == 0, "miss-null");
	}
	/* Reentrant: hit, miss, tiny buffer. */
	{
		struct passwd pwb; char buf[16384]; struct passwd *res = 0;
		errno = 0;
		check(getpwnam_r("sinew-u1", &pwb, buf, sizeof buf, &res) == 0 &&
		      res == &pwb && pwb.pw_uid == 61001, "r-hit");
		errno = 0;
		check(getpwnam_r("no-such-user-sinew", &pwb, buf, sizeof buf, &res) == 0 &&
		      res == 0, "r-miss");
		/* _r functions return the error number (not -1/errno). */
		{
			char tiny[8]; struct passwd *r2 = 0;
			errno = 0;
			check(getpwnam_r("sinew-u1", &pwb, tiny, sizeof tiny, &r2) == ERANGE &&
			      r2 == 0, "r-tiny-erange");
		}
	}
	/* Group lookup + members. */
	errno = 0; gr = getgrnam("sinew-g2");
	check(gr && gr->gr_gid == 61102 && gr->gr_mem[0] &&
	      !strcmp(gr->gr_mem[0], "sinew-u1") && gr->gr_mem[1] &&
	      !strcmp(gr->gr_mem[1], "sinew-u2") && gr->gr_mem[2] == 0,
	      "grp-members");
	errno = 0; gr = getgrgid(61101);
	check(gr && !strcmp(gr->gr_name, "sinew-g1"), "grp-byid");
	errno = 0; gr = getgrnam("no-such-group-sinew");
	check(gr == 0, "grp-miss-null");
	{
		struct group grb; char buf[16384]; struct group *res = 0;
		errno = 0;
		check(getgrgid_r(61102, &grb, buf, sizeof buf, &res) == 0 &&
		      res == &grb, "gr-r-hit");
		{
			char tiny[8]; struct group *r2 = 0;
			errno = 0;
			check(getgrgid_r(61102, &grb, tiny, sizeof tiny, &r2) == ERANGE &&
			      r2 == 0, "gr-r-tiny-erange");
		}
	}
	/* Supplementary list: primary gid first, then file order. */
	{
		gid_t groups[16]; int n = 16, i;
		for (i = 0; i < 16; i++) groups[i] = 0;
		errno = 0;
		check(getgrouplist("sinew-u1", 61001, groups, &n) == 3 && n == 3 &&
		      groups[0] == 61001 && groups[1] == 61101 &&
		      groups[2] == 61102, "grouplist-exact");
	}
	{
		gid_t g1; int n = 0;
		errno = 0;
		check(getgrouplist("sinew-u1", 61001, &g1, &n) < 0 && n == 3,
		      "grouplist-small");
	}
	/* Shadow (readable fixture, namespace-root): exact fields. */
	errno = 0; sp = getspnam("sinew-u1");
	check(sp && !strcmp(sp->sp_namp, "sinew-u1") &&
	      !strcmp(sp->sp_pwdp, "!"), "shadow-fields");
	errno = 0; sp = getspnam("no-such-user-sinew");
	check(sp == 0, "shadow-miss-null");
	/* Enumeration: count + file order. */
	{
		int n = 0; struct passwd *e;
		char f[32], l[32];
		f[0] = l[0] = '\0';
		setpwent();
		while ((e = getpwent()) != 0 && n < 100) {
			if (!n) snprintf(f, sizeof f, "%s", e->pw_name);
			snprintf(l, sizeof l, "%s", e->pw_name);
			n++;
		}
		endpwent();
		printf("info enum count=%d first=%s last=%s\n", n, f, l);
		check(n == 2 && !strcmp(f, "sinew-u1") && !strcmp(l, "sinew-u2"),
		      "enum-order-count");
	}
	/* fgetpwent on the bound-over passwd path: must not crash;
	 * first good entry must be reachable. */
	{
		FILE *fp = fopen("/etc/passwd", "r");
		struct passwd *e = 0;
		if (fp) { e = fgetpwent(fp); }
		printf("info fget-first=%s\n", e ? e->pw_name : "(null)");
		check(e != 0, "fget-first-nonnull");
		if (fp) fclose(fp);
	}
	if (fails) { printf("RESULT: %d FAILURES\n", fails); return 1; }
	printf("RESULT: ALL PASS\n");
	return 0;
}
EOF
$CC -O2 -Wall -o "$root/t_dyn" "$root/t.c"
if command -v musl-static-gcc >/dev/null 2>&1; then
	TC=musl-static-gcc
elif [ -x /opt/saphira/musl-static/bin/musl-static-gcc ]; then
	TC=/opt/saphira/musl-static/bin/musl-static-gcc
else
	TC=""
fi
if [ -n "$TC" ]; then $TC -O2 -Wall -o "$root/t_stc" "$root/t.c"; fi
run_phase() {
	unshare --user --map-root-user --mount sh -c "
		mount --bind $root/fix/passwd.$1 /etc/passwd &&
		mount --bind $root/fix/group.$1 /etc/group &&
		mount --bind $root/fix/shadow.$1 /etc/shadow &&
		if [ -e /etc/nsswitch.conf ]; then
			mount --bind $root/fix/nsswitch.conf /etc/nsswitch.conf;
		fi &&
		exec \"\$0\"" "$root/$2"
}
echo "=== clean / dynamic ==="; run_phase clean t_dyn
if [ -n "$TC" ]; then echo "=== clean / static ==="; run_phase clean t_stc; fi
echo "=== malformed / dynamic ==="; run_phase bad t_dyn

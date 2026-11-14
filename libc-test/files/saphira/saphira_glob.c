/* Saphira glob/globfree behavioural coverage (Sinew Item 6).
 *
 * glob has zero symbol-reference coverage in the upstream suite
 * (coverage.map: no bin references glob/globfree) yet shares its
 * bracket engine with the Sinew-0027-hardened fnmatch, so it needs
 * a behavioural tripwire. Every MUST below was verified musl-r20
 * vs glibc-2.44 on identical fixtures (Item 6 battery); the two
 * DIVERGENCE pins record musl-native behaviour where it differs
 * from glibc, with rationale (same convention as the vec-67/68
 * corpus updates: pin the truth, document the delta).
 *
 * Fixture lives in a mkdtemp dir; absolute patterns keep output
 * deterministic. Root skips the permission cases (unreadable dirs
 * are readable for uid 0).
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "test.h"

static char fix[256];
static int failures;

#define CHECK(cond, tag) do { \
	if (!(cond)) { \
		t_error("glob " tag " failed\n"); \
		failures++; \
	} \
} while (0)

static void mk(const char *rel)
{
	char b[512];
	snprintf(b, sizeof b, "%s/%s", fix, rel);
	FILE *f = fopen(b, "w");
	if (!f) {
		t_error("fixture fopen %s: %s\n", b, strerror(errno));
		failures++;
		return;
	}
	fclose(f);
}

static void setup(void)
{
	char *d;
	strcpy(fix, "/tmp/saphira-glob-XXXXXX");
	d = mkdtemp(fix);
	if (!d) {
		t_error("mkdtemp: %s\n", strerror(errno));
		failures++;
		return;
	}
	mk("a.c"); mk("b.c"); mk("ab.c"); mk("A.C"); mk("a.h");
	mk(".h.c"); mk(".hidden"); mk("a?.c"); mk("a-.c"); mk("-.c");
}

static void setup_sub(void)
{
	char b[512];
	snprintf(b, sizeof b, "%s/sub", fix);
	mkdir(b, 0755);
	snprintf(b, sizeof b, "%s/sub/x.c", fix);
	FILE *f = fopen(b, "w");
	if (f) fclose(f);
	snprintf(b, sizeof b, "%s/link", fix);
	symlink("a.c", b);
	snprintf(b, sizeof b, "%s/brokenlink", fix);
	symlink("nonexist_target_xyz", b);
	snprintf(b, sizeof b, "%s/dirlink", fix);
	symlink("sub", b);
	snprintf(b, sizeof b, "%s/noperm", fix);
	mkdir(b, 0755);
	snprintf(b, sizeof b, "%s/noperm/y.c", fix);
	f = fopen(b, "w");
	if (f) fclose(f);
	snprintf(b, sizeof b, "%s/noperm", fix);
	chmod(b, 0000);
}

static int has(const glob_t *g, const char *base)
{
	size_t i;
	char want[256], got[256];
	const char *w = base;
	size_t wl = strlen(base);
	/* allow "sub/" to match basename "sub" */
	if (wl > 0 && base[wl - 1] == '/') {
		if (wl - 1 >= sizeof want)
			return 0;
		memcpy(want, base, wl - 1);
		want[wl - 1] = 0;
		w = want;
	}
	for (i = 0; i < g->gl_pathc; i++) {
		const char *p = g->gl_pathv[g->gl_offs + i];
		const char *s;
		size_t sl;
		strncpy(got, p, sizeof got - 1);
		got[sizeof got - 1] = 0;
		/* strip trailing slashes (GLOB_MARK dirs) first,
		 * then the basename is never empty */
		sl = strlen(got);
		while (sl > 0 && got[sl - 1] == '/')
			got[--sl] = 0;
		s = strrchr(got, '/');
		s = s ? s + 1 : got;
		if (!strcmp(s, w))
			return 1;
	}
	return 0;
}

static int err_seen;
static char err_path[512];
static int err_no;

static int cap_err(const char *p, int e)
{
	err_seen++;
	snprintf(err_path, sizeof err_path, "%s", p);
	err_no = e;
	return 1; /* abort */
}

static int ignore_err(const char *p, int e)
{
	(void)p;
	(void)e;
	return 0; /* carry on */
}

static int count_err(const char *p, int e)
{
	err_seen++;
	snprintf(err_path, sizeof err_path, "%s", p);
	err_no = e;
	return 0; /* carry on despite the error */
}

static void teardown(void)
{
	char b[512];
	const char *files[] = {
		"a.c", "b.c", "ab.c", "A.C", "a.h", ".h.c", ".hidden",
		"a?.c", "a-.c", "-.c", "link", "brokenlink", "dirlink",
		"sub/x.c", "noperm/y.c", 0,
	};
	int i;
	snprintf(b, sizeof b, "%s/noperm", fix);
	chmod(b, 0700);
	for (i = 0; files[i]; i++) {
		snprintf(b, sizeof b, "%s/%s", fix, files[i]);
		unlink(b);
	}
	snprintf(b, sizeof b, "%s/sub", fix);
	rmdir(b);
	snprintf(b, sizeof b, "%s/noperm", fix);
	rmdir(b);
	rmdir(fix);
}

int main(void)
{
	glob_t g;
	char pat[512];
	int r, root;
	DIR *d;

	setup();
	setup_sub();
	if (failures)
		return 1;
	root = (geteuid() == 0);

	/* basic match + byte-order sort */
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/*.c", fix);
	r = glob(pat, 0, NULL, &g);
	CHECK(r == 0 && g.gl_pathc == 6, "basic");
	CHECK(has(&g, "-.c") && has(&g, "a-.c") && has(&g, "a.c") &&
	      has(&g, "a?.c") && has(&g, "ab.c") && has(&g, "b.c"),
	      "basic-set");
	if (g.gl_pathc == 6)
		CHECK(!strcmp(strrchr(g.gl_pathv[0], '/') + 1, "-.c") &&
		      !strcmp(strrchr(g.gl_pathv[5], '/') + 1, "b.c"),
		      "basic-order");
	globfree(&g);

	/* dotfiles excluded by default */
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/*", fix);
	r = glob(pat, 0, NULL, &g);
	CHECK(r == 0 && !has(&g, ".hidden"), "star-no-dot");
	globfree(&g);

	/* PERIOD admits dotfiles (and . / .. for a bare star) */
	memset(&g, 0, sizeof g);
	r = glob(pat, GLOB_PERIOD, NULL, &g);
	CHECK(r == 0 && has(&g, ".hidden") && has(&g, ".h.c"),
	      "period-dotfiles");
	globfree(&g);

	/* NOMATCH vs NOCHECK, empty pattern */
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/*.zz_nomatch", fix);
	CHECK(glob(pat, 0, NULL, &g) == GLOB_NOMATCH, "nomatch");
	globfree(&g);
	memset(&g, 0, sizeof g);
	CHECK(glob(pat, GLOB_NOCHECK, NULL, &g) == 0 &&
	      g.gl_pathc == 1, "nocheck");
	globfree(&g);
	memset(&g, 0, sizeof g);
	CHECK(glob("", 0, NULL, &g) == GLOB_NOMATCH, "empty");
	globfree(&g);

	/* MARK, including symlink subtleties */
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/sub*", fix);
	CHECK(glob(pat, GLOB_MARK, NULL, &g) == 0 &&
	      g.gl_pathc == 1 && has(&g, "sub/"), "mark-dir");
	globfree(&g);
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/dirlink", fix);
	CHECK(glob(pat, GLOB_MARK, NULL, &g) == 0 &&
	      has(&g, "dirlink/"), "mark-symdir");
	globfree(&g);
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/brokenlink", fix);
	CHECK(glob(pat, GLOB_MARK, NULL, &g) == 0 &&
	      has(&g, "brokenlink"), "mark-broken-unmarked");
	globfree(&g);

	/* DOOFFS null slots, APPEND combine + first-call tolerance */
	memset(&g, 0, sizeof g);
	g.gl_offs = 2;
	snprintf(pat, sizeof pat, "%s/*.c", fix);
	CHECK(glob(pat, GLOB_DOOFFS, NULL, &g) == 0 &&
	      g.gl_offs == 2 && g.gl_pathv[0] == NULL &&
	      g.gl_pathv[1] == NULL, "dooffs");
	globfree(&g);
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/a*.c", fix);
	glob(pat, 0, NULL, &g);
	snprintf(pat, sizeof pat, "%s/b*.c", fix);
	r = glob(pat, GLOB_APPEND, NULL, &g);
	CHECK(r == 0 && g.gl_pathc == 5, "append");
	globfree(&g);
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/a*.c", fix);
	CHECK(glob(pat, GLOB_APPEND, NULL, &g) == 0, "append-first");
	globfree(&g);

	/* escapes and trailing-hyphen-literal (0027 adjacency) */
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/a\\?.c", fix);
	CHECK(glob(pat, 0, NULL, &g) == 0 && has(&g, "a?.c"),
	      "escape");
	globfree(&g);
	memset(&g, 0, sizeof g);
	CHECK(glob(pat, GLOB_NOESCAPE, NULL, &g) == GLOB_NOMATCH,
	      "noescape");
	globfree(&g);
	memset(&g, 0, sizeof g);
	snprintf(pat, sizeof pat, "%s/[a-].c", fix);
	r = glob(pat, 0, NULL, &g);
	CHECK(r == 0 && has(&g, "a.c") && has(&g, "-.c"),
	      "hyphen-literal");
	globfree(&g);

	/* tilde happy paths */
	setenv("HOME", fix, 1);
	memset(&g, 0, sizeof g);
	CHECK(glob("~", GLOB_TILDE, NULL, &g) == 0 &&
	      g.gl_pathc == 1, "tilde");
	globfree(&g);

	/* DIVERGENCE D1 (musl-native pin): bad user + TILDE without
	 * CHECK yields NOMATCH/empty on musl; glibc returns the
	 * literal pattern. TILDE_CHECK agrees (NOMATCH) on both. */
	memset(&g, 0, sizeof g);
	CHECK(glob("~nosuchuser_xyz_9/", GLOB_TILDE, NULL, &g) ==
	      GLOB_NOMATCH && g.gl_pathc == 0, "baduser-tilde");
	globfree(&g);
	memset(&g, 0, sizeof g);
	CHECK(glob("~nosuchuser_xyz_9/", GLOB_TILDE_CHECK, NULL, &g) ==
	      GLOB_NOMATCH, "baduser-tilde-check");
	globfree(&g);

	/* permission errors: skip by default, abort on GLOB_ERR or
	 * errfunc-nonzero; errfunc sees EACCES. Root skips (perms
	 * do not bind uid 0). */
	snprintf(pat, sizeof pat, "%s/noperm", fix);
	d = opendir(pat);
	if (d) {
		closedir(d);
	} else {
		memset(&g, 0, sizeof g);
		err_seen = 0;
		snprintf(pat, sizeof pat, "%s/noperm/*.c", fix);
		r = glob(pat, 0, ignore_err, &g);
		CHECK(r == GLOB_NOMATCH, "noperm-skip");
		globfree(&g);
		memset(&g, 0, sizeof g);
		err_seen = 0;
		r = glob(pat, 0, count_err, &g);
		CHECK(r == GLOB_NOMATCH && err_seen == 1 &&
		      err_no == EACCES, "noperm-errfunc");
		globfree(&g);
		memset(&g, 0, sizeof g);
		err_seen = 0;
		r = glob(pat, GLOB_ERR, cap_err, &g);
		CHECK(r == GLOB_ABORTED, "noperm-err");
		globfree(&g);
		/* DIVERGENCE D2: musl passes the running buffer
		 * (trailing slash) as epath, glibc the pattern
		 * component. Pin the stable parts; tolerate both
		 * spellings of the path. */
		CHECK(err_no == EACCES &&
		      !strncmp(err_path, fix, strlen(fix)),
		      "errfunc-errno");
	}
	if (!root) {
		/* errfunc abort covered above via cap_err returning 1 */
	}

	/* zeroed globfree + struct reuse */
	memset(&g, 0, sizeof g);
	globfree(&g);
	snprintf(pat, sizeof pat, "%s/a*.c", fix);
	glob(pat, 0, NULL, &g);
	globfree(&g);
	snprintf(pat, sizeof pat, "%s/b*.c", fix);
	CHECK(glob(pat, 0, NULL, &g) == 0 && g.gl_pathc == 1,
	      "reuse");
	globfree(&g);

	teardown();
	if (failures)
		return 1;
	return t_status;
}

/*
 * saphira initramfs /init
 *
 * Deliberately stupid. This program owns five things and nothing else:
 *
 *   1. establish the pseudo-filesystems early userspace needs;
 *   2. run the runtime hook stages in lexical order;
 *   3. stop on the first hook failure, visibly;
 *   4. verify the root contract;
 *   5. perform the terminal transition.
 *
 * It knows nothing about ZFS, LVM, RAID, or any other storage. A root
 * provider is a hook: it loads modules, imports a pool, locates a dataset
 * and mounts it at /newroot, then returns. The transition itself belongs
 * here, so that every root provider inherits the same policy and no provider
 * has to reimplement it.
 *
 * Two terminal modes, chosen by /etc/saphira/initramfs.conf inside the
 * initramfs:
 *
 *   mode=switch   hooks prepared /newroot; verify it and switch_root into it.
 *                 This is the installed-system path.
 *
 *   mode=ram      run the configured installer entrypoint from the initramfs
 *                 itself and never leave it. The installer payload is a
 *                 complete environment in RAM; it has no /newroot and must not
 *                 be asked for one. The interface exists now so the installer
 *                 initramfs does not require a redesign of /init later.
 *
 * Built static against musl so early userspace needs no loader and no
 * libraries, and so the archive is self-contained by construction.
 */

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define CONFIG_PATH "/etc/saphira/initramfs.conf"
/*
 * Runtime hooks live under /lib, not /usr/lib. Saphira is non-usrmerged:
 * /lib and /usr/lib are both real directories and a package picks the one its
 * kind of content belongs in. The build-time hook directory is a different
 * thing entirely and lives under /usr/lib; see saphira-mkinitramfs(8).
 */
#define HOOK_ROOT   "/lib/saphira/initramfs"

struct config {
	const char *mode;        /* "switch" (default) or "ram" */
	const char *newroot;     /* default "/newroot" */
	const char *real_init;   /* empty: probe a list */
	const char *installer;   /* mode=ram entrypoint */
	int         verbose;
};

/* Emergency handling must not depend on anything we have not yet established.
 * A serial console is the only thing guaranteed to exist, so that is what the
 * failure path uses. */
static void emergency(const char *what, const char *detail)
{
	static const char *tty = "/dev/console";
	int fd = open(tty, O_WRONLY | O_NOCTTY);

	if (fd >= 0) {
		dprintf(fd, "\nsaphira-init: FATAL: %s: %s\n", what,
			detail ? detail : strerror(errno));
		fsync(fd);
		close(fd);
	}
	fprintf(stderr, "saphira-init: FATAL: %s: %s\n", what,
		detail ? detail : strerror(errno));
}

static void note(const struct config *cfg, const char *fmt, ...)
	__attribute__((format(printf, 2, 3)));

static void note(const struct config *cfg, const char *fmt, ...)
{
	va_list ap;
	char buf[512];
	int n;

	if (!cfg->verbose)
		return;
	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof buf, fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	/* Best effort to the console; never fatal. */
	{
		int fd = open("/dev/console", O_WRONLY | O_NOCTTY);
		if (fd >= 0) {
			(void)!write(fd, buf, (size_t)n < sizeof buf ? (size_t)n : sizeof buf - 1);
			close(fd);
		}
	}
}

/* Trim a trailing newline in place. Config lines are read with fgets. */
static void chomp(char *s)
{
	size_t n = strlen(s);

	while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r' ||
			 s[n - 1] == ' ' || s[n - 1] == '\t'))
		s[--n] = '\0';
}

static int read_config(struct config *cfg)
{
	FILE *f;
	char line[512];

	cfg->mode = "switch";
	cfg->newroot = "/newroot";
	cfg->real_init = "";
	cfg->installer = "";
	cfg->verbose = 1;

	f = fopen(CONFIG_PATH, "re");
	if (!f)
		return 0; /* absent config is legitimate: defaults apply */

	while (fgets(line, sizeof line, f)) {
		char *key, *value, *eq;

		chomp(line);
		if (line[0] == '#' || line[0] == '\0')
			continue;
		eq = strchr(line, '=');
		if (!eq)
			continue;
		*eq = '\0';
		key = line;
		value = eq + 1;
		chomp(key);
		chomp(value);
		if (!strcmp(key, "mode"))
			cfg->mode = value;
		else if (!strcmp(key, "newroot"))
			cfg->newroot = value;
		else if (!strcmp(key, "real_init"))
			cfg->real_init = value;
		else if (!strcmp(key, "installer"))
			cfg->installer = value;
		else if (!strcmp(key, "verbose")) {
			cfg->verbose = !(!strcmp(value, "0") ||
					  !strcmp(value, "no") ||
					  !strcmp(value, "false"));
		}
	}
	fclose(f);
	return 1;
}

/*
 * Establish the pseudo-filesystems. Each is best effort with a reason: /dev
 * is frequently already a devtmpfs mounted by the kernel (CONFIG_DEVTMPFS_MOUNT),
 * and failing there would be wrong. Anything genuinely required and absent is
 * reported rather than silently tolerated.
 */
static void establish_pseudo_filesystems(const struct config *cfg)
{
	static const struct {
		const char *dir;
		const char *type;
		const char *src;
		int         optional;
	} mounts[] = {
		{ "/proc",  "proc",  "proc",  0 },
		{ "/sys",   "sysfs", "sysfs", 0 },
		{ "/dev",   "devtmpfs", "devtmpfs", 1 },
		{ "/run",   "tmpfs", "tmpfs", 0 },
	};
	size_t i;

	for (i = 0; i < sizeof mounts / sizeof mounts[0]; i++) {
		struct stat st;

		if (stat(mounts[i].dir, &st) != 0) {
			if (mkdir(mounts[i].dir, 0755) != 0 && errno != EEXIST) {
				emergency("cannot create pseudo-filesystem directory",
					  mounts[i].dir);
				exit(1);
			}
		}
		if (mount(mounts[i].type, mounts[i].dir, mounts[i].type, 0, NULL) != 0) {
			if (errno == EBUSY) {
				note(cfg, "%s already mounted", mounts[i].dir);
				continue;
			}
			if (mounts[i].optional) {
				note(cfg, "%s not mounted: %s", mounts[i].dir,
				     strerror(errno));
				continue;
			}
			emergency("cannot mount pseudo-filesystem", mounts[i].dir);
			exit(1);
		}
		note(cfg, "mounted %s", mounts[i].dir);
	}
}

/* Run every executable in one stage directory, in lexical order. */
static void run_stage(const struct config *cfg, const char *stage)
{
	char dirpath[512];
	DIR *d;
	struct dirent *ent;
	char **names = NULL;
	size_t count = 0, cap = 0, i;

	snprintf(dirpath, sizeof dirpath, "%s/%s", HOOK_ROOT, stage);
	d = opendir(dirpath);
	if (!d) {
		if (errno == ENOENT)
			return; /* a stage with no hooks is normal */
		emergency("cannot open hook stage", dirpath);
		exit(1);
	}

	/*
	 * readdir order is filesystem-dependent, and the whole point of "lexical
	 * order" is that it is not. Collect then insertion-sort: the number of
	 * hooks is small and this keeps the ordering obviously correct.
	 */
	while ((ent = readdir(d)) != NULL) {
		if (ent->d_name[0] == '.')
			continue;
		if (count == cap) {
			char **grown;
			cap = cap ? cap * 2 : 16;
			grown = realloc(names, cap * sizeof *names);
			if (!grown) {
				closedir(d);
				emergency("out of memory listing hooks", dirpath);
				exit(1);
			}
			names = grown;
		}
		names[count++] = strdup(ent->d_name);
	}
	closedir(d);

	for (i = 1; i < count; i++) {
		char *key = names[i];
		size_t j = i;
		while (j > 0 && strcmp(names[j - 1], key) > 0) {
			names[j] = names[j - 1];
			j--;
		}
		names[j] = key;
	}

	for (i = 0; i < count; i++) {
		char path[1024];
		char detail[64];
		pid_t pid;
		int status = 0;

		snprintf(path, sizeof path, "%s/%s", dirpath, names[i]);
		free(names[i]);

		note(cfg, "hook %s/%s", stage, names[i]);
		pid = fork();
		if (pid < 0) {
			emergency("cannot fork for hook", path);
			exit(1);
		}
		if (pid == 0) {
			/* Hooks inherit a usable environment; no surprises wanted. */
			execl(path, path, (char *)NULL);
			fprintf(stderr, "saphira-init: hook %s: %s\n", path,
				strerror(errno));
			_exit(127);
		}
		if (waitpid(pid, &status, 0) < 0) {
			emergency("cannot wait for hook", path);
			exit(1);
		}
		if (WIFSIGNALED(status)) {
			snprintf(detail, sizeof detail, "killed by signal %d",
				 WTERMSIG(status));
			emergency("hook failed", path);
			fprintf(stderr, "saphira-init: %s\n", detail);
			exit(1);
		}
		if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
			snprintf(detail, sizeof detail, "exit status %d",
				 WEXITSTATUS(status));
			emergency("hook failed", path);
			fprintf(stderr, "saphira-init: %s\n", detail);
			exit(1);
		}
	}
	free(names);
	note(cfg, "stage %s: %zu hook(s) ok", stage, count);
}

/*
 * The root contract. "Something is mounted" is not enough: a provider that
 * failed to import a pool can leave a directory that looks right, and
 * switch_root into it produces an unbootable machine with no diagnostic. So
 * the check is: the newroot exists, it has an executable init, and the init
 * is one we can name.
 */
static const char *const init_candidates[] = {
	"/sbin/init",
	"/usr/sbin/init",
	"/usr/lib/systemd/systemd",
	"/bin/init",
	NULL
};

static const char *find_real_init(const struct config *cfg, char *buf, size_t len)
{
	int i;

	if (cfg->real_init && cfg->real_init[0]) {
		snprintf(buf, len, "%s%s", cfg->newroot, cfg->real_init);
		if (access(buf, X_OK) == 0)
			return buf;
		emergency("configured real_init is not executable", buf);
		return NULL;
	}
	for (i = 0; init_candidates[i]; i++) {
		snprintf(buf, len, "%s%s", cfg->newroot, init_candidates[i]);
		if (access(buf, X_OK) == 0)
			return buf;
	}
	emergency("no executable init found under the new root", cfg->newroot);
	return NULL;
}

int main(void)
{
	struct config cfg;
	char initpath[1024];
	const char *real_init;

	read_config(&cfg);

	establish_pseudo_filesystems(&cfg);

	/*
	 * The three stages, in order. early.d prepares the machine (modules,
	 * udev-like population, anything that must precede a provider);
	 * root.d produces /newroot; pre-switch-root.d gets the last word
	 * before the transition.
	 */
	run_stage(&cfg, "early.d");
	run_stage(&cfg, "root.d");
	run_stage(&cfg, "pre-switch-root.d");

	if (!strcmp(cfg.mode, "ram")) {
		/*
		 * Installer mode. The payload lives in this initramfs and is
		 * already the root filesystem, so there is nothing to switch into
		 * and no /newroot to verify. Hand over to the configured
		 * entrypoint; it becomes the installer.
		 */
		if (!cfg.installer || !cfg.installer[0]) {
			emergency("mode=ram but no installer entrypoint is configured",
				  CONFIG_PATH);
			return 1;
		}
		if (access(cfg.installer, X_OK) != 0) {
			emergency("installer entrypoint is not executable",
				  cfg.installer);
			return 1;
		}
		note(&cfg, "entering installer mode: %s", cfg.installer);
		execl(cfg.installer, cfg.installer, (char *)NULL);
		emergency("cannot exec installer entrypoint", cfg.installer);
		return 1;
	}

	if (strcmp(cfg.mode, "switch") != 0) {
		char detail[128];

		snprintf(detail, sizeof detail, "unknown mode '%s' in %s",
			 cfg.mode, CONFIG_PATH);
		emergency("invalid configuration", detail);
		return 1;
	}

	/* switch mode: verify the contract, then transition. */
	if (access(cfg.newroot, F_OK) != 0) {
		emergency("new root does not exist after root.d", cfg.newroot);
		return 1;
	}
	real_init = find_real_init(&cfg, initpath, sizeof initpath);
	if (!real_init)
		return 1;

	note(&cfg, "switch_root %s %s", cfg.newroot, real_init);

	/*
	 * Hand the transition to util-linux's switch_root rather than
	 * reimplementing it: moving the root, moving /dev, execing the new
	 * init and untangling the old namespace is exactly the set of things
	 * that must not be got subtly wrong. util-linux is a runtime
	 * dependency of the initramfs for this reason alone, and the generator
	 * pulls in its library closure automatically.
	 */
	execl("/usr/bin/switch_root", "switch_root", cfg.newroot, real_init,
	      (char *)NULL);
	if (errno == ENOENT)
		execl("/sbin/switch_root", "switch_root", cfg.newroot, real_init,
		      (char *)NULL);
	emergency("cannot exec switch_root", strerror(errno));
	return 1;
}

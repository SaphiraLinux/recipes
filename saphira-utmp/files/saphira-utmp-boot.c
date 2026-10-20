/* saphira-utmp-boot: record one BOOT_TIME entry per kernel boot.
 *
 * Stage4 boot accounting for OpenRC (and for systemd built with
 * -Dutmp=false, which is musl-mandated): neither init path writes
 * utmp/wtmp records on Saphira, so coreutils uptime/who -b fell back
 * to image-file mtimes (the 50-day Egg uptime scare: utmp was empty,
 * gnulib synthesized boot time from /var/lib/systemd/random-seed).
 * This tool writes exactly one BOOT_TIME record per kernel boot,
 * keyed on the kernel's own btime, and is a strict no-op otherwise
 * (restart-safe: re-running changes nothing).
 *
 * Files (SAPHIRA_UTMP_ROOT may prefix both, for hermetic testing):
 *   /var/run/utmp  created 0644 root:root if missing; a BOOT_TIME
 *                   record for the current btime is appended iff none
 *                   is present. Never truncated, never rewritten.
 *   /var/log/wtmp  created 0644 root:root if missing; a BOOT_TIME
 *                   record for the current btime is appended iff the
 *                   last record is not already this boot's.
 * Never invents a time: btime comes from /proc/stat; an unreadable
 * btime or a corrupt utmp fails LOUD (exit 1) instead of writing
 * fiction. Callers (the boot service) surface that failure visibly.
 */

#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <utmpx.h>

static const char *root_prefix(void)
{
	const char *r = getenv("SAPHIRA_UTMP_ROOT");
	return r != NULL ? r : "";
}

/* The kernel's own boot time. Returns 0 with *t set, -1 loud. */
static int read_btime(time_t *t)
{
	FILE *f = fopen("/proc/stat", "r");
	char line[256];
	if (f == NULL) {
		fprintf(stderr, "saphira-utmp-boot: cannot open /proc/stat: %s\n",
			strerror(errno));
		return -1;
	}
	while (fgets(line, sizeof line, f) != NULL) {
		unsigned long long b;
		if (sscanf(line, "btime %llu", &b) == 1) {
			fclose(f);
			*t = (time_t)b;
			return 0;
		}
	}
	fclose(f);
	fprintf(stderr, "saphira-utmp-boot: no btime in /proc/stat\n");
	return -1;
}

static void fill_boot_record(struct utmpx *u, time_t boot_time)
{
	memset(u, 0, sizeof *u);
	u->ut_type = BOOT_TIME;
	u->ut_pid = 1;
	memcpy(u->ut_line, "~", 2);
	memcpy(u->ut_id, "~~", 3);
	memcpy(u->ut_user, "reboot", 7);
	u->ut_tv.tv_sec = boot_time;
	u->ut_tv.tv_usec = 0;
}

/* Ensure utmp holds this boot's record. 0 done, -1 loud failure. */
static int ensure_utmp(const char *path, time_t boot_time)
{
	struct utmpx u;
	int fd = open(path, O_RDWR | O_CREAT, 0644);
	ssize_t n;
	if (fd < 0) {
		fprintf(stderr, "saphira-utmp-boot: cannot open %s: %s\n",
			path, strerror(errno));
		return -1;
	}
	while ((n = read(fd, &u, sizeof u)) == (ssize_t)sizeof u) {
		if (u.ut_type == BOOT_TIME && u.ut_tv.tv_sec == boot_time) {
			close(fd);
			return 0;
		}
	}
	if (n != 0) {
		fprintf(stderr, "saphira-utmp-boot: corrupt record in %s\n",
			path);
		close(fd);
		return -1;
	}
	fill_boot_record(&u, boot_time);
	if (write(fd, &u, sizeof u) != (ssize_t)sizeof u) {
		fprintf(stderr, "saphira-utmp-boot: cannot write %s: %s\n",
			path, strerror(errno));
		close(fd);
		return -1;
	}
	fsync(fd);
	close(fd);
	return 0;
}

/* Append this boot's record to wtmp unless the last record already
 * is it. 0 done, -1 loud failure. */
static int ensure_wtmp(const char *path, time_t boot_time)
{
	struct utmpx u;
	off_t end;
	int fd = open(path, O_RDWR | O_CREAT, 0644);
	ssize_t n;
	if (fd < 0) {
		fprintf(stderr, "saphira-utmp-boot: cannot open %s: %s\n",
			path, strerror(errno));
		return -1;
	}
	end = lseek(fd, 0, SEEK_END);
	if (end < 0) {
		fprintf(stderr, "saphira-utmp-boot: cannot seek %s: %s\n",
			path, strerror(errno));
		close(fd);
		return -1;
	}
	if (end >= (off_t)sizeof u) {
		if (lseek(fd, -(off_t)sizeof u, SEEK_END) < 0) {
			fprintf(stderr, "saphira-utmp-boot: cannot seek %s: %s\n",
				path, strerror(errno));
			close(fd);
			return -1;
		}
		n = read(fd, &u, sizeof u);
		if (n != (ssize_t)sizeof u) {
			fprintf(stderr, "saphira-utmp-boot: corrupt tail in %s\n",
				path);
			close(fd);
			return -1;
		}
		if (u.ut_type == BOOT_TIME && u.ut_tv.tv_sec == boot_time) {
			close(fd);
			return 0;
		}
		if (lseek(fd, 0, SEEK_END) < 0) {
			fprintf(stderr, "saphira-utmp-boot: cannot seek %s: %s\n",
				path, strerror(errno));
			close(fd);
			return -1;
		}
	}
	fill_boot_record(&u, boot_time);
	if (write(fd, &u, sizeof u) != (ssize_t)sizeof u) {
		fprintf(stderr, "saphira-utmp-boot: cannot write %s: %s\n",
			path, strerror(errno));
		close(fd);
		return -1;
	}
	fsync(fd);
	close(fd);
	return 0;
}

int main(int argc, char **argv)
{
	char utmp_path[4096];
	char wtmp_path[4096];
	time_t boot_time;
	const char *root = root_prefix();
	if (argc == 2
	    && (strcmp(argv[1], "--help") == 0
		|| strcmp(argv[1], "-h") == 0)) {
		printf("usage: saphira-utmp-boot\n"
		       "\n"
		       "Record one BOOT_TIME entry per kernel boot in\n"
		       "$SAPHIRA_UTMP_ROOT/var/run/utmp and\n"
		       "$SAPHIRA_UTMP_ROOT/var/log/wtmp (root defaults to /).\n"
		       "No-op when this boot is already recorded.\n");
		return 0;
	}
	if (argc != 1) {
		fprintf(stderr, "usage: saphira-utmp-boot [--help]\n");
		return 2;
	}
	if (snprintf(utmp_path, sizeof utmp_path, "%s/var/run/utmp",
		     root) >= (int)sizeof utmp_path
	    || snprintf(wtmp_path, sizeof wtmp_path, "%s/var/log/wtmp",
			root) >= (int)sizeof wtmp_path) {
		fprintf(stderr, "saphira-utmp-boot: root prefix too long\n");
		return 1;
	}
	if (read_btime(&boot_time) != 0)
		return 1;
	if (ensure_utmp(utmp_path, boot_time) != 0)
		return 1;
	if (ensure_wtmp(wtmp_path, boot_time) != 0)
		return 1;
	return 0;
}

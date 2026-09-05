/*
 * update-ca-certificates - Saphira native certificate bundle builder.
 *
 * Reads /etc/ca-certificates.conf (one relative path per line under
 * /usr/share/ca-certificates, '#' comments), symlinks every enabled
 * certificate into /etc/ssl/certs/, appends /usr/local/share/
 * ca-certificates/*.crt, and concatenates the enabled set into
 * /etc/ssl/certs/ca-certificates.crt via mkstemp + rename.
 * Hooks: run-parts /etc/ca-certificates/update.d
 */
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define CONF "/etc/ca-certificates.conf"
#define CERTSDIR "/usr/share/ca-certificates/"
#define LOCALDIR "/usr/local/share/ca-certificates/"
#define OUTDIR "/etc/ssl/certs/"
#define BUNDLE OUTDIR "ca-certificates.crt"

static int bundle_fd = -1;
static int count = 0;

static void bundle_append(const char *path)
{
	char buf[65536];
	int fd = open(path, O_RDONLY);
	ssize_t r;
	if (fd < 0) {
		fprintf(stderr, "Warning! Cannot hash: %s\n", path);
		return;
	}
	while ((r = read(fd, buf, sizeof buf)) > 0) {
		if (write(bundle_fd, buf, r) != r) {
			fprintf(stderr, "Warning! Cannot copy to bundle: %s\n", path);
			break;
		}
	}
	close(fd);
	count++;
}

static void link_cert(const char *rel)
{
	char src[4096], dst[4096];
	const char *base = strrchr(rel, '/');
	base = base ? base + 1 : rel;
	snprintf(src, sizeof src, CERTSDIR "%s", rel);
	snprintf(dst, sizeof dst, OUTDIR "%s", base);
	(void)unlink(dst);
	if (symlink(src, dst) != 0 && errno != EEXIST)
		fprintf(stderr, "Warning! Cannot update symlink %s -> %s\n",
			dst, src);
}

static void process_local(void)
{
	DIR *d = opendir(LOCALDIR);
	struct dirent *e;
	char src[4096], dst[4096];
	if (!d)
		return;
	while ((e = readdir(d))) {
		size_t len = strlen(e->d_name);
		if (len < 5 || strcmp(e->d_name + len - 4, ".crt"))
			continue;
		snprintf(src, sizeof src, LOCALDIR "%s", e->d_name);
		snprintf(dst, sizeof dst, OUTDIR "%s", e->d_name);
		(void)unlink(dst);
		symlink(src, dst);
		bundle_append(src);
	}
	closedir(d);
}

int main(void)
{
	FILE *conf;
	char line[4096];
	char tmp[] = OUTDIR "bundleXXXXXX";

	mkdir(OUTDIR, 0755);
	conf = fopen(CONF, "r");
	if (!conf) {
		perror("Cannot open path: " CONF);
		return 1;
	}
	bundle_fd = mkstemp(tmp);
	if (bundle_fd < 0) {
		fprintf(stderr, "Failed to open temporary file %s for ca bundle\n", tmp);
		return 1;
	}
	/* mkstemp creates 0600; the bundle is world-readable trust material */
	fchmod(bundle_fd, 0644);
	while (fgets(line, sizeof line, conf)) {
		char *p = line, *nl;
		while (*p == ' ' || *p == '\t')
			p++;
		if (*p == '#' || *p == '\n' || !*p)
			continue;
		nl = strchr(p, '\n');
		if (nl)
			*nl = '\0';
		link_cert(p);
		{
			char path[4096];
			snprintf(path, sizeof path, CERTSDIR "%s", p);
			bundle_append(path);
		}
	}
	fclose(conf);
	process_local();
	if (close(bundle_fd) != 0) {
		perror("bundle write");
		unlink(tmp);
		return 1;
	}
	if (rename(tmp, BUNDLE) != 0) {
		perror("rename bundle");
		unlink(tmp);
		return 1;
	}
	printf("Updating certificates in %s: %d added, "
	       "obtained from %s\n", OUTDIR, count, CONF);
	execl("/usr/bin/run-parts", "run-parts",
	      "/etc/ca-certificates/update.d", (char *)NULL);
	if (errno == ENOENT)
		return 0;
	perror("run-parts");
	return 1;
}
